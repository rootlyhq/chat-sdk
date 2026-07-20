# frozen_string_literal: true

require_relative "../../spec_helper"
require "rack"

RSpec.describe ChatSDK::Linear::Adapter do
  subject do
    described_class.new(
      api_key: api_key,
      webhook_secret: webhook_secret,
      bot_username: bot_username
    )
  end

  let(:api_key) { "test-linear-api-key" }
  let(:webhook_secret) { "test-webhook-secret" }
  let(:bot_username) { "TestBot" }

  it_behaves_like "a chat_sdk platform adapter"

  describe "#initialize" do
    it "raises ConfigurationError without api_key" do
      expect { described_class.new(api_key: nil, webhook_secret: webhook_secret) }
        .to raise_error(ChatSDK::ConfigurationError, /api_key required/)
    end

    it "raises ConfigurationError without webhook_secret" do
      expect { described_class.new(api_key: api_key, webhook_secret: nil) }
        .to raise_error(ChatSDK::ConfigurationError, /webhook_secret required/)
    end

    it "falls back to environment variables" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LINEAR_API_KEY").and_return("env-key")
      allow(ENV).to receive(:[]).with("LINEAR_WEBHOOK_SECRET").and_return("env-secret")
      allow(ENV).to receive(:[]).with("LINEAR_BOT_USERNAME").and_return("env-bot")

      adapter = described_class.new
      expect(adapter.name).to eq(:linear)
    end
  end

  describe "#name" do
    it "returns :linear" do
      expect(subject.name).to eq(:linear)
    end
  end

  describe "#client" do
    it "returns an ApiClient" do
      expect(subject.client).to be_a(ChatSDK::Linear::ApiClient)
    end
  end

  describe "#mention" do
    it "formats a Linear mention with @" do
      expect(subject.mention("quentin")).to eq("@quentin")
    end
  end

  describe "#verify_request!" do
    def build_signed_request(body)
      signature = OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, body)

      env = Rack::MockRequest.env_for(
        "/webhooks/linear",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json",
        "HTTP_LINEAR_SIGNATURE" => signature
      )
      Rack::Request.new(env)
    end

    def build_request(body, signature: "invalidhash")
      env = Rack::MockRequest.env_for(
        "/webhooks/linear",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json",
        "HTTP_LINEAR_SIGNATURE" => signature
      )
      Rack::Request.new(env)
    end

    it "accepts a valid HMAC-SHA256 signature" do
      body = '{"test":"data"}'
      request = build_signed_request(body)
      expect(subject.verify_request!(request)).to be(true)
    end

    it "rejects an invalid signature" do
      body = '{"test":"data"}'
      request = build_request(body, signature: "invalidhash")
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Invalid Linear signature/)
    end

    it "rejects missing signature header" do
      env = Rack::MockRequest.env_for(
        "/webhooks/linear",
        :method => "POST",
        :input => '{"test":"data"}',
        "CONTENT_TYPE" => "application/json"
      )
      request = Rack::Request.new(env)
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Missing Linear signature/)
    end
  end

  describe "#ack_response" do
    it "returns nil for any request" do
      env = Rack::MockRequest.env_for("/webhooks/linear", method: "POST")
      request = Rack::Request.new(env)
      expect(subject.ack_response(request)).to be_nil
    end
  end

  describe "#parse_events" do
    def build_request(body)
      env = Rack::MockRequest.env_for(
        "/webhooks/linear",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json"
      )
      Rack::Request.new(env)
    end

    context "comment create events" do
      it "parses a comment into a Mention event" do
        payload = {
          "type" => "Comment",
          "action" => "create",
          "data" => {
            "id" => "comment-123",
            "body" => "@TestBot help me with this issue",
            "issueId" => "issue-456",
            "user" => {"id" => "user-789", "name" => "Quentin"}
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Mention)
        expect(event.message.id).to eq("comment-123")
        expect(event.message.text).to eq("@TestBot help me with this issue")
        expect(event.message.author.id).to eq("user-789")
        expect(event.message.author.name).to eq("Quentin")
        expect(event.thread_id).to eq("linear:issue-456:c:comment-123")
        expect(event.channel_id).to eq("issue-456")
        expect(event.platform).to eq(:linear)
        expect(event.adapter_name).to eq(:linear)
      end

      it "skips comments from the bot itself" do
        payload = {
          "type" => "Comment",
          "action" => "create",
          "data" => {
            "id" => "comment-999",
            "body" => "I am the bot",
            "issueId" => "issue-456",
            "user" => {"id" => "bot-id", "name" => bot_username}
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events).to be_empty
      end
    end

    context "non-comment types" do
      it "returns empty array for Issue events" do
        payload = {
          "type" => "Issue",
          "action" => "create",
          "data" => {"id" => "issue-123", "title" => "New issue"}
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events).to be_empty
      end

      it "returns empty array for Reaction events" do
        payload = {
          "type" => "Reaction",
          "action" => "create",
          "data" => {"id" => "reaction-123", "emoji" => "thumbsup"}
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events).to be_empty
      end
    end

    context "invalid JSON" do
      it "returns empty array" do
        request = build_request("not json")
        events = subject.parse_events(request)
        expect(events).to be_empty
      end
    end

    context "empty payload" do
      it "returns empty array" do
        request = build_request("{}")
        events = subject.parse_events(request)
        expect(events).to be_empty
      end
    end
  end

  describe "#post_message" do
    it "creates a comment on an issue" do
      stub_request(:post, "https://api.linear.app/graphql")
        .to_return(
          status: 200,
          body: JSON.generate({
            "data" => {
              "commentCreate" => {
                "success" => true,
                "comment" => {
                  "id" => "comment-new-1",
                  "body" => "Hello Linear!",
                  "user" => {"id" => "bot-id", "name" => "TestBot"}
                }
              }
            }
          }),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.post_message(channel_id: "issue-456", message: "Hello Linear!")
      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("comment-new-1")
      expect(result.platform).to eq(:linear)
      expect(result.thread_id).to eq("linear:issue-456:c:comment-new-1")
    end

    it "creates a reply comment when thread_id contains :c:" do
      stub_request(:post, "https://api.linear.app/graphql")
        .with { |req|
          body = JSON.parse(req.body)
          body.dig("variables", "input", "parentId") == "parent-comment-1"
        }
        .to_return(
          status: 200,
          body: JSON.generate({
            "data" => {
              "commentCreate" => {
                "success" => true,
                "comment" => {
                  "id" => "comment-reply-1",
                  "body" => "Reply!",
                  "user" => {"id" => "bot-id", "name" => "TestBot"}
                }
              }
            }
          }),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.post_message(
        channel_id: "issue-456",
        message: "Reply!",
        thread_id: "linear:issue-456:c:parent-comment-1"
      )
      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("comment-reply-1")
    end
  end

  describe "#add_reaction" do
    it "creates a reaction on a comment" do
      stub_request(:post, "https://api.linear.app/graphql")
        .with { |req|
          body = JSON.parse(req.body)
          body.dig("variables", "input", "commentId") == "comment-123" &&
            body.dig("variables", "input", "emoji") == "thumbsup"
        }
        .to_return(
          status: 200,
          body: JSON.generate({"data" => {"reactionCreate" => {"success" => true}}}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.add_reaction(channel_id: "issue-1", message_id: "comment-123", emoji: "thumbsup") }
        .not_to raise_error
    end
  end

  describe "#remove_reaction" do
    it "deletes a reaction from a comment" do
      stub_request(:post, "https://api.linear.app/graphql")
        .with { |req|
          body = JSON.parse(req.body)
          body.dig("variables", "input", "commentId") == "comment-123" &&
            body.dig("variables", "input", "emoji") == "thumbsup"
        }
        .to_return(
          status: 200,
          body: JSON.generate({"data" => {"reactionDelete" => {"success" => true}}}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.remove_reaction(channel_id: "issue-1", message_id: "comment-123", emoji: "thumbsup") }
        .not_to raise_error
    end
  end

  describe "capability gaps" do
    it "raises NotSupportedError for edit_message" do
      expect { subject.edit_message(channel_id: "C1", message_id: "M1", message: "test") }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "raises NotSupportedError for delete_message" do
      expect { subject.delete_message(channel_id: "C1", message_id: "M1") }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "raises NotSupportedError for ephemeral messages" do
      expect { subject.post_ephemeral(channel_id: "C1", user_id: "U1", message: "test") }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "raises NotSupportedError for modals" do
      expect { subject.open_modal(trigger_id: "T1", modal: ChatSDK::Cards::Node.new(:modal)) }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "raises NotSupportedError for typing indicator" do
      expect { subject.start_typing(channel_id: "C1") }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "raises NotSupportedError for file uploads" do
      expect { subject.upload_file(channel_id: "C1", io: StringIO.new("data"), filename: "test.txt") }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "raises NotSupportedError for fetch_messages" do
      expect { subject.fetch_messages(channel_id: "C1") }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "raises NotSupportedError for open_dm" do
      expect { subject.open_dm("U1") }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "does not support edit_messages capability" do
      expect(subject.supports?(:edit_messages)).to be false
    end

    it "does not support modals capability" do
      expect(subject.supports?(:modals)).to be false
    end

    it "does not support typing_indicator capability" do
      expect(subject.supports?(:typing_indicator)).to be false
    end

    it "does not support direct_messages capability" do
      expect(subject.supports?(:direct_messages)).to be false
    end

    it "supports reactions capability" do
      expect(subject.supports?(:reactions)).to be true
    end
  end
end
