# frozen_string_literal: true

require_relative "../../spec_helper"
require "rack"
require "base64"
require "openssl"

RSpec.describe ChatSDK::GitLab::Adapter do
  subject(:adapter) do
    described_class.new(
      token: "gitlab-token",
      webhook_secret: "webhook-secret",
      api_url: api_url,
      bot_user_id: "99",
      bot_username: "gitlab-bot"
    )
  end

  let(:api_url) { "https://gitlab.example.test/api/v4" }
  let(:thread_id) { "gitlab:42:mr:3:abcdef" }
  let(:channel_id) { "gitlab:42" }

  it_behaves_like "a chat_sdk platform adapter"

  def build_request(body, event_type: "Note Hook", headers: {})
    env = {
      "HTTP_X_GITLAB_EVENT" => event_type,
      "HTTP_X_GITLAB_TOKEN" => "webhook-secret"
    }.merge(headers)
    Rack::Request.new(Rack::MockRequest.env_for(
      "/webhooks/gitlab",
      {method: "POST", input: body}.merge(env)
    ))
  end

  def note_payload(text: "Please review @gitlab-bot", user_id: 5, noteable_type: "MergeRequest",
    discussion_id: "abcdef", extra: {})
    payload = {
      "object_kind" => "note",
      "project_id" => 42,
      "user" => {"id" => user_id, "name" => "Alice", "username" => "alice"},
      "object_attributes" => {
        "id" => 501,
        "note" => text,
        "noteable_type" => noteable_type,
        "discussion_id" => discussion_id,
        "created_at" => "2025-01-01T10:00:00Z"
      },
      "merge_request" => {"iid" => 3},
      "issue" => {"iid" => 8}
    }
    payload.merge(extra)
  end

  def json_request(payload, event_type: "Note Hook")
    build_request(JSON.generate(payload), event_type: event_type)
  end

  def note_response(id: 501, body: "Reply")
    {
      "id" => id,
      "body" => body,
      "author" => {"id" => 99, "name" => "GitLab bot", "username" => "gitlab-bot"},
      "created_at" => "2025-01-01T10:00:00Z"
    }
  end

  describe "#initialize" do
    it "requires a token and at least one webhook verifier" do
      expect { described_class.new(token: nil, webhook_secret: "secret") }
        .to raise_error(ChatSDK::ConfigurationError, /GITLAB_TOKEN/)
      expect { described_class.new(token: "token") }
        .to raise_error(ChatSDK::ConfigurationError, /GITLAB_WEBHOOK/)
    end

    it "decodes a Standard Webhooks signing token with or without its prefix" do
      key = Base64.strict_encode64("k" * 32)

      expect(described_class.new(token: "token", webhook_signing_token: key).name).to eq(:gitlab)
      expect(described_class.new(token: "token", webhook_signing_token: "whsec_#{key}").name).to eq(:gitlab)
    end

    it "uses GitLab environment defaults" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("GITLAB_TOKEN").and_return("env-token")
      allow(ENV).to receive(:[]).with("GITLAB_WEBHOOK_SECRET").and_return("env-secret")

      configured = described_class.new

      expect(configured.name).to eq(:gitlab)
      expect(configured.bot_username).to eq("gitlab-bot")
    end
  end

  describe "#verify_request!" do
    it "accepts a matching X-Gitlab-Token" do
      expect(adapter.verify_request!(build_request("{}"))).to be(true)
    end

    it "rejects an incorrect secret token" do
      request = build_request("{}", headers: {"HTTP_X_GITLAB_TOKEN" => "wrong"})

      expect { adapter.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError)
    end

    it "accepts any valid v1 Standard Webhooks signature" do
      key = "k" * 32
      signing_adapter = described_class.new(
        token: "gitlab-token",
        webhook_signing_token: Base64.strict_encode64(key),
        api_url: api_url
      )
      body = "{}"
      message_id = "event-1"
      timestamp = Time.now.to_i.to_s
      digest = OpenSSL::HMAC.digest("SHA256", key, "#{message_id}.#{timestamp}.#{body}")
      valid_signature = "v1,#{Base64.strict_encode64(digest)}"
      request = build_request(body, headers: {
        "HTTP_WEBHOOK_ID" => message_id,
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
        "HTTP_WEBHOOK_SIGNATURE" => "v1,invalid #{valid_signature}"
      })

      expect(signing_adapter.verify_request!(request)).to be(true)
    end

    it "rejects an expired Standard Webhooks signature" do
      key = "k" * 32
      signing_adapter = described_class.new(
        token: "gitlab-token",
        webhook_signing_token: Base64.strict_encode64(key),
        api_url: api_url
      )
      body = "{}"
      message_id = "event-1"
      timestamp = (Time.now.to_i - 600).to_s
      digest = OpenSSL::HMAC.digest("SHA256", key, "#{message_id}.#{timestamp}.#{body}")
      request = build_request(body, headers: {
        "HTTP_WEBHOOK_ID" => message_id,
        "HTTP_WEBHOOK_TIMESTAMP" => timestamp,
        "HTTP_WEBHOOK_SIGNATURE" => "v1,#{Base64.strict_encode64(digest)}"
      })

      expect { signing_adapter.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError)
    end
  end

  describe "#parse_events" do
    it "parses merge request notes and masks code spans for mention detection" do
      event = adapter.parse_events(json_request(note_payload)).first

      expect(event).to be_a(ChatSDK::Events::Mention)
      expect(event.thread_id).to eq("gitlab:42:mr:3:abcdef")
      expect(event.channel_id).to eq("gitlab:42")
      expect(event.message.author.id).to eq("5")
      expect(event.message.is_mention).to be(true)

      code_event = adapter.parse_events(json_request(note_payload(text: "`@gitlab-bot` is code"))).first
      expect(code_event.message.is_mention).to be(false)
    end

    it "parses issue notes without a discussion ID" do
      payload = note_payload(
        text: "Issue note",
        noteable_type: "Issue",
        discussion_id: nil
      )

      event = adapter.parse_events(json_request(payload)).first

      expect(event.thread_id).to eq("gitlab:42:issue:8")
      expect(event.message.text).to eq("Issue note")
    end

    it "ignores system notes, bot-authored notes, and unsupported noteables" do
      system_payload = note_payload(extra: {"object_attributes" => {
        "id" => 501, "note" => "system", "noteable_type" => "MergeRequest", "system" => true
      }})
      bot_payload = note_payload(user_id: 99)
      commit_payload = note_payload(extra: {"object_attributes" => {
        "id" => 501, "note" => "commit", "noteable_type" => "Commit"
      }})
      internal_payload = note_payload(extra: {"object_attributes" => {
        "id" => 501, "note" => "internal", "noteable_type" => "MergeRequest", "internal" => true
      }})
      confidential_payload = note_payload(
        noteable_type: "Issue",
        extra: {"issue" => {"iid" => 8, "confidential" => true}}
      )

      expect(adapter.parse_events(json_request(system_payload))).to be_empty
      expect(adapter.parse_events(json_request(bot_payload))).to be_empty
      expect(adapter.parse_events(json_request(commit_payload))).to be_empty
      expect(adapter.parse_events(json_request(internal_payload))).to be_empty
      expect(adapter.parse_events(json_request(confidential_payload))).to be_empty
    end

    it "parses Emoji Hook awards as reaction events" do
      payload = {
        "object_kind" => "emoji",
        "event_type" => "award",
        "project_id" => 42,
        "object_attributes" => {"awardable_type" => "Note", "name" => "thumbsup", "user_id" => 5},
        "note" => {"id" => 501, "noteable_type" => "Issue", "discussion_id" => "abcdef"},
        "issue" => {"iid" => 8},
        "user" => {"id" => 5}
      }

      event = adapter.parse_events(json_request(payload, event_type: "Emoji Hook")).first

      expect(event).to be_a(ChatSDK::Events::Reaction)
      expect(event.emoji).to eq("thumbs_up")
      expect(event.added?).to be(true)
      expect(event.thread_id).to eq("gitlab:42:issue:8:abcdef")
    end

    it "does not cache a failed lazy bot identity lookup" do
      configured = described_class.new(token: "gitlab-token", webhook_secret: "secret", api_url: api_url)
      lookup = stub_request(:get, "#{api_url}/user")
        .to_return(
          {status: 500, body: '{"message":"unavailable"}', headers: {"Content-Type" => "application/json"}},
          {status: 200, body: '{"id":99,"username":"gitlab-bot"}', headers: {"Content-Type" => "application/json"}}
        )
      request = json_request(note_payload)

      expect(configured.parse_events(request)).to be_empty
      expect(configured.parse_events(request)).to contain_exactly(an_instance_of(ChatSDK::Events::Mention))
      expect(lookup).to have_been_requested.twice
    end

    it "caches identity after a successful lazy lookup" do
      configured = described_class.new(token: "gitlab-token", webhook_secret: "secret", api_url: api_url)
      lookup = stub_request(:get, "#{api_url}/user")
        .to_return(status: 200, body: '{"id":99,"username":"gitlab-bot"}', headers: {"Content-Type" => "application/json"})
      request = json_request(note_payload)

      expect(configured.parse_events(request)).to contain_exactly(an_instance_of(ChatSDK::Events::Mention))
      expect(configured.parse_events(request)).to contain_exactly(an_instance_of(ChatSDK::Events::Mention))
      expect(lookup).to have_been_requested.once
    end
  end

  describe "outbound API methods" do
    it "posts a discussion reply and returns a normalized message" do
      endpoint = "#{api_url}/projects/42/merge_requests/3/discussions/abcdef/notes"
      stub_request(:post, endpoint)
        .with(headers: {"Authorization" => "Bearer gitlab-token"}, body: {"body" => "Reply"})
        .to_return(status: 201, body: JSON.generate(note_response), headers: {"Content-Type" => "application/json"})

      message = adapter.post_message(channel_id: channel_id, thread_id: thread_id, message: "Reply")

      expect(message.id).to eq("501")
      expect(message.text).to eq("Reply")
      expect(message.thread_id).to eq(thread_id)
      expect(message.author.bot?).to be(true)
    end

    it "edits and deletes numeric note IDs" do
      edit_endpoint = "#{api_url}/projects/42/issues/8/notes/501"
      delete_endpoint = edit_endpoint
      issue_thread = "gitlab:42:issue:8"
      stub_request(:put, edit_endpoint)
        .with(body: {"body" => "Edited"})
        .to_return(status: 200, body: JSON.generate(note_response(body: "Edited")), headers: {"Content-Type" => "application/json"})
      stub_request(:delete, delete_endpoint).to_return(status: 204)

      edited = adapter.edit_message(
        channel_id: channel_id,
        thread_id: issue_thread,
        message_id: "501",
        message: "Edited"
      )
      deleted = adapter.delete_message(
        channel_id: channel_id,
        thread_id: issue_thread,
        message_id: "501"
      )

      expect(edited.text).to eq("Edited")
      expect(deleted).to eq({})
    end

    it "posts a new top-level issue note" do
      endpoint = "#{api_url}/projects/42/issues/8/notes"
      stub_request(:post, endpoint)
        .with(body: {"body" => "New issue comment"})
        .to_return(status: 201, body: JSON.generate(note_response(body: "New issue comment")), headers: {"Content-Type" => "application/json"})

      message = adapter.post_message(
        channel_id: channel_id,
        thread_id: "gitlab:42:issue:8",
        message: "New issue comment"
      )

      expect(message.text).to eq("New issue comment")
      expect(WebMock).to have_requested(:post, endpoint).once
    end

    it "adds and removes the bot's award emoji" do
      award_endpoint = "#{api_url}/projects/42/merge_requests/3/notes/501/award_emoji"
      stub_request(:post, award_endpoint)
        .with(body: {"name" => "thumbsup"})
        .to_return(status: 201, body: '{"name":"thumbsup"}', headers: {"Content-Type" => "application/json"})
      stub_request(:get, award_endpoint).with(query: {"page" => "1", "per_page" => "100"})
        .to_return(status: 200, body: '[{"id":700,"name":"thumbsup","user":{"id":99}}]', headers: {"Content-Type" => "application/json"})
      stub_request(:delete, "#{award_endpoint}/700").to_return(status: 204)

      adapter.add_reaction(channel_id: channel_id, thread_id: thread_id, message_id: "501", emoji: "thumbs_up")
      adapter.remove_reaction(channel_id: channel_id, thread_id: thread_id, message_id: "501", emoji: "thumbs_up")

      expect(WebMock).to have_requested(:post, award_endpoint).once
      expect(WebMock).to have_requested(:delete, "#{award_endpoint}/700").once
    end

    it "uses the GitLab page cursor for note history" do
      endpoint = "#{api_url}/projects/42/merge_requests/3/notes"
      stub_request(:get, endpoint)
        .with(query: {"order_by" => "created_at", "sort" => "desc", "per_page" => "2", "page" => "2"})
        .to_return(
          status: 200,
          body: JSON.generate([note_response(id: 502), note_response(id: 501)]),
          headers: {"Content-Type" => "application/json", "X-Next-Page" => "3"}
        )

      messages, cursor = adapter.fetch_messages(
        channel_id: channel_id,
        thread_id: "gitlab:42:mr:3",
        cursor: "2",
        limit: 2
      )

      expect(messages.map(&:id)).to eq(%w[501 502])
      expect(cursor).to eq("3")
    end

    it "fetches discussion notes without a page cursor" do
      endpoint = "#{api_url}/projects/42/merge_requests/3/discussions/abcdef"
      stub_request(:get, endpoint)
        .to_return(status: 200, body: JSON.generate({"notes" => [note_response]}), headers: {"Content-Type" => "application/json"})

      messages, cursor = adapter.fetch_messages(channel_id: channel_id, thread_id: thread_id)

      expect(messages.map(&:id)).to eq(["501"])
      expect(cursor).to be_nil
    end

    it "rejects invalid thread and note IDs before making a request" do
      endpoint = "#{api_url}/projects/42/merge_requests/3/notes"

      expect do
        adapter.post_message(channel_id: channel_id, thread_id: "gitlab:42:mr:3:XYZ", message: "bad")
      end.to raise_error(ArgumentError)
      expect do
        adapter.delete_message(channel_id: channel_id, thread_id: "gitlab:42:mr:3", message_id: "1;drop")
      end.to raise_error(ArgumentError)
      expect(WebMock).not_to have_requested(:post, endpoint)
      expect(WebMock).not_to have_requested(:delete, endpoint)
    end

    it "maps API failures to platform and rate-limit errors" do
      endpoint = "#{api_url}/projects/42/issues/8/notes"
      stub_request(:post, endpoint)
        .to_return(status: 422, body: '{"message":"body is invalid"}', headers: {"Content-Type" => "application/json"})

      error = nil
      begin
        adapter.post_message(channel_id: channel_id, thread_id: "gitlab:42:issue:8", message: "Bad")
      rescue ChatSDK::PlatformError => raised
        error = raised
      end
      expect(error.status).to eq(422)
      expect(error.body).to eq({"message" => "body is invalid"})
      expect(error.adapter_name).to eq(:gitlab)

      rate_limited_adapter = described_class.new(
        token: "gitlab-token",
        webhook_secret: "webhook-secret",
        api_url: api_url,
        bot_user_id: "99",
        bot_username: "gitlab-bot"
      )
      stub_request(:post, endpoint)
        .to_return(status: 429, body: '{"message":"slow down"}', headers: {
          "Content-Type" => "application/json",
          "Retry-After" => "0"
        })

      expect do
        rate_limited_adapter.post_message(channel_id: channel_id, thread_id: "gitlab:42:issue:8", message: "Again")
      end.to raise_error(ChatSDK::RateLimitedError) { |raised| expect(raised.adapter_name).to eq(:gitlab) }
    end
  end

  describe "#mention and #start_typing" do
    it "formats username mentions and validates no-op typing calls" do
      expect(adapter.mention("alice")).to eq("@alice")
      expect(adapter.start_typing(channel_id: channel_id, thread_id: thread_id)).to be_nil
    end
  end
end
