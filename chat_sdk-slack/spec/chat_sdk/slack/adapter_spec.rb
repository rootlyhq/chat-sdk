# frozen_string_literal: true

require_relative "../../spec_helper"
require "openssl"
require "rack"

RSpec.describe ChatSDK::Slack::Adapter do
  subject { described_class.new(bot_token: bot_token, signing_secret: signing_secret) }

  let(:bot_token) { "xoxb-test-token-12345" }
  let(:signing_secret) { "test_signing_secret_abc123" }

  it_behaves_like "a chat_sdk platform adapter"

  describe "#initialize" do
    it "raises ConfigurationError without bot_token or client_id" do
      expect { described_class.new(bot_token: nil, signing_secret: signing_secret) }
        .to raise_error(ChatSDK::ConfigurationError, /bot_token or client_id required/)
    end

    it "raises ConfigurationError without signing_secret" do
      expect { described_class.new(bot_token: bot_token, signing_secret: nil) }
        .to raise_error(ChatSDK::ConfigurationError, /signing_secret required/)
    end
  end

  describe "#name" do
    it "returns :slack" do
      expect(subject.name).to eq(:slack)
    end
  end

  describe "#client" do
    it "returns a Slack::Web::Client" do
      expect(subject.client).to be_a(::Slack::Web::Client)
    end
  end

  describe "#verify_request!" do
    def build_signed_request(body, secret: signing_secret, timestamp: Time.now.to_i.to_s)
      sig_basestring = "v0:#{timestamp}:#{body}"
      hex_digest = OpenSSL::HMAC.hexdigest("SHA256", secret, sig_basestring)
      signature = "v0=#{hex_digest}"

      env = Rack::MockRequest.env_for(
        "/slack/events",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_SLACK_REQUEST_TIMESTAMP" => timestamp,
        "HTTP_X_SLACK_SIGNATURE" => signature
      )
      Rack::Request.new(env)
    end

    it "accepts a valid signature" do
      body = '{"type":"event_callback"}'
      request = build_signed_request(body)
      expect(subject.verify_request!(request)).to be(true)
    end

    it "rejects an invalid signature" do
      body = '{"type":"event_callback"}'
      request = build_signed_request(body, secret: "wrong_secret")
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Invalid Slack signature/)
    end

    it "rejects missing signature headers" do
      env = Rack::MockRequest.env_for(
        "/slack/events",
        :method => "POST",
        :input => '{"type":"event_callback"}',
        "CONTENT_TYPE" => "application/json"
      )
      request = Rack::Request.new(env)
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Missing Slack signature headers/)
    end

    it "rejects requests that are too old" do
      body = '{"type":"event_callback"}'
      old_timestamp = (Time.now.to_i - 600).to_s
      request = build_signed_request(body, timestamp: old_timestamp)
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /too old/)
    end
  end

  describe "#ack_response" do
    it "returns challenge response for url_verification" do
      body = '{"type":"url_verification","challenge":"test_challenge_xyz"}'
      env = Rack::MockRequest.env_for(
        "/slack/events",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json"
      )
      request = Rack::Request.new(env)
      result = subject.ack_response(request)
      expect(result).to eq([200, {"content-type" => "text/plain"}, ["test_challenge_xyz"]])
    end

    it "returns nil for non-verification events" do
      body = '{"type":"event_callback","event":{}}'
      env = Rack::MockRequest.env_for(
        "/slack/events",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json"
      )
      request = Rack::Request.new(env)
      expect(subject.ack_response(request)).to be_nil
    end
  end

  describe "#parse_events" do
    def build_request(body, content_type: "application/json")
      env = Rack::MockRequest.env_for(
        "/slack/events",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => content_type
      )
      Rack::Request.new(env)
    end

    context "app_mention event" do
      it "parses into a Mention event" do
        payload = {
          "type" => "event_callback",
          "event" => {
            "type" => "app_mention",
            "user" => "U123",
            "text" => "<@B456> hello bot",
            "ts" => "1234567890.123456",
            "channel" => "C789"
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Mention)
        expect(event.message.text).to eq("<@B456> hello bot")
        expect(event.message.author.id).to eq("U123")
        expect(event.channel_id).to eq("C789")
        expect(event.platform).to eq(:slack)
        expect(event.adapter_name).to eq(:slack)
      end
    end

    context "message event (channel)" do
      it "parses into a SubscribedMessage event" do
        payload = {
          "type" => "event_callback",
          "event" => {
            "type" => "message",
            "user" => "U123",
            "text" => "hello channel",
            "ts" => "1234567890.123456",
            "channel" => "C789",
            "channel_type" => "channel"
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        expect(events.first).to be_a(ChatSDK::Events::SubscribedMessage)
        expect(events.first.message.text).to eq("hello channel")
      end
    end

    context "message event (DM)" do
      it "parses into a DirectMessage event" do
        payload = {
          "type" => "event_callback",
          "event" => {
            "type" => "message",
            "user" => "U123",
            "text" => "hello dm",
            "ts" => "1234567890.123456",
            "channel" => "D789",
            "channel_type" => "im"
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        expect(events.first).to be_a(ChatSDK::Events::DirectMessage)
        expect(events.first.message.text).to eq("hello dm")
      end
    end

    context "message event from bot" do
      it "ignores bot messages" do
        payload = {
          "type" => "event_callback",
          "event" => {
            "type" => "message",
            "bot_id" => "B123",
            "text" => "bot message",
            "ts" => "1234567890.123456",
            "channel" => "C789"
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)
        expect(events).to be_empty
      end
    end

    context "message event with subtype" do
      it "ignores messages with subtypes other than file_share" do
        payload = {
          "type" => "event_callback",
          "event" => {
            "type" => "message",
            "subtype" => "message_changed",
            "user" => "U123",
            "text" => "edited",
            "ts" => "1234567890.123456",
            "channel" => "C789"
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)
        expect(events).to be_empty
      end
    end

    context "reaction_added event" do
      it "parses into a Reaction event" do
        payload = {
          "type" => "event_callback",
          "event" => {
            "type" => "reaction_added",
            "user" => "U123",
            "reaction" => "thumbsup",
            "item" => {"ts" => "1234567890.123456", "channel" => "C789"}
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Reaction)
        expect(event.emoji).to eq("thumbsup")
        expect(event.user_id).to eq("U123")
        expect(event.added?).to be true
      end
    end

    context "reaction_removed event" do
      it "parses into a Reaction event with added=false" do
        payload = {
          "type" => "event_callback",
          "event" => {
            "type" => "reaction_removed",
            "user" => "U123",
            "reaction" => "thumbsup",
            "item" => {"ts" => "1234567890.123456", "channel" => "C789"}
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        expect(events.first.added?).to be false
        expect(events.first.removed?).to be true
      end
    end

    context "block_actions" do
      it "parses into Action events" do
        payload = {
          "type" => "block_actions",
          "user" => {"id" => "U123", "name" => "testuser"},
          "channel" => {"id" => "C789"},
          "message" => {"ts" => "1234567890.123456"},
          "trigger_id" => "T999",
          "actions" => [
            {"action_id" => "btn:approve", "value" => "yes"}
          ]
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Action)
        expect(event.action_id).to eq("btn:approve")
        expect(event.value).to eq("yes")
        expect(event.user.id).to eq("U123")
        expect(event.trigger_id).to eq("T999")
      end
    end

    context "block_actions via form-encoded payload" do
      it "parses the payload parameter" do
        inner = {
          "type" => "block_actions",
          "user" => {"id" => "U123", "name" => "testuser"},
          "channel" => {"id" => "C789"},
          "message" => {"ts" => "1234567890.123456"},
          "trigger_id" => "T999",
          "actions" => [
            {"action_id" => "btn:ok", "value" => "clicked"}
          ]
        }
        body = "payload=#{Rack::Utils.escape(JSON.generate(inner))}"
        request = build_request(body, content_type: "application/x-www-form-urlencoded")
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        expect(events.first.action_id).to eq("btn:ok")
      end
    end

    context "slash command" do
      it "parses form-encoded slash command" do
        body = Rack::Utils.build_query(
          "command" => "/incident",
          "text" => "create server down",
          "user_id" => "U123",
          "channel_id" => "C789",
          "trigger_id" => "T999"
        )
        request = build_request(body, content_type: "application/x-www-form-urlencoded")
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::SlashCommand)
        expect(event.command).to eq("/incident")
        expect(event.text).to eq("create server down")
        expect(event.user_id).to eq("U123")
        expect(event.channel_id).to eq("C789")
      end
    end
  end

  describe "#get_user" do
    it "returns an Author for a valid user" do
      allow(subject.client).to receive(:users_info)
        .with(user: "U123")
        .and_return({
          "ok" => true,
          "user" => {"id" => "U123", "name" => "alice", "is_bot" => false}
        })

      result = subject.get_user("U123")
      expect(result).to be_a(ChatSDK::Author)
      expect(result.id).to eq("U123")
      expect(result.name).to eq("alice")
      expect(result.platform).to eq(:slack)
      expect(result.bot?).to be false
    end

    it "returns an Author with bot: true for bot users" do
      allow(subject.client).to receive(:users_info)
        .with(user: "B456")
        .and_return({
          "ok" => true,
          "user" => {"id" => "B456", "name" => "helperbot", "is_bot" => true}
        })

      result = subject.get_user("B456")
      expect(result).to be_a(ChatSDK::Author)
      expect(result.bot?).to be true
    end
  end

  describe "#schedule_message" do
    it "schedules a message and returns a Message" do
      post_at = Time.now.to_i + 3600

      allow(subject.client).to receive(:chat_scheduleMessage)
        .with(channel: "C789", text: "Reminder!", post_at: post_at)
        .and_return({
          "ok" => true,
          "channel" => "C789",
          "scheduled_message_id" => "Q1234ABCD",
          "post_at" => post_at
        })

      result = subject.schedule_message(channel_id: "C789", message: "Reminder!", post_at: post_at)

      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("Q1234ABCD")
      expect(result.text).to eq("Reminder!")
      expect(result.channel_id).to eq("C789")
      expect(result.platform).to eq(:slack)
      expect(result.thread_id).to eq("Q1234ABCD")
    end

    it "schedules a threaded message" do
      post_at = Time.now.to_i + 3600

      allow(subject.client).to receive(:chat_scheduleMessage)
        .with(channel: "C789", text: "Follow-up", post_at: post_at, thread_ts: "1234567890.123456")
        .and_return({
          "ok" => true,
          "channel" => "C789",
          "scheduled_message_id" => "Q5678EFGH",
          "post_at" => post_at
        })

      result = subject.schedule_message(
        channel_id: "C789",
        message: "Follow-up",
        post_at: post_at,
        thread_id: "1234567890.123456"
      )

      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("Q5678EFGH")
      expect(result.thread_id).to eq("1234567890.123456")
    end
  end

  describe "#publish_home_view" do
    it "publishes a home tab view" do
      view = {type: "home", blocks: [{type: "section", text: {type: "mrkdwn", text: "Hello"}}]}

      allow(subject.client).to receive(:views_publish)
        .with(user_id: "U123", view: view)
        .and_return({"ok" => true})

      expect { subject.publish_home_view(user_id: "U123", view: view) }
        .not_to raise_error
    end
  end

  describe "#set_suggested_prompts" do
    it "sets suggested prompts on a thread" do
      prompts = [{title: "Summarize", message: "Summarize this thread"}]

      allow(subject.client).to receive(:assistant_threads_setSuggestedPrompts)
        .with(channel_id: "C123", thread_ts: "1234.5678", prompts: prompts)
        .and_return({"ok" => true})

      expect { subject.set_suggested_prompts(channel_id: "C123", thread_id: "1234.5678", prompts: prompts) }
        .not_to raise_error
    end
  end

  describe "#set_assistant_status" do
    it "sets assistant status on a thread" do
      allow(subject.client).to receive(:assistant_threads_setStatus)
        .with(channel_id: "C123", thread_ts: "1234.5678", status: "Thinking...")
        .and_return({"ok" => true})

      expect { subject.set_assistant_status(channel_id: "C123", thread_id: "1234.5678", status: "Thinking...") }
        .not_to raise_error
    end
  end

  describe "#set_assistant_title" do
    it "sets assistant title on a thread" do
      allow(subject.client).to receive(:assistant_threads_setTitle)
        .with(channel_id: "C123", thread_ts: "1234.5678", title: "Incident Summary")
        .and_return({"ok" => true})

      expect { subject.set_assistant_title(channel_id: "C123", thread_id: "1234.5678", title: "Incident Summary") }
        .not_to raise_error
    end
  end

  describe "#mention" do
    it "formats a Slack user mention" do
      expect(subject.mention("U123")).to eq("<@U123>")
    end
  end

  describe "multi-workspace OAuth" do
    let(:multi_adapter) do
      described_class.new(
        client_id: "test-client-id",
        client_secret: "test-client-secret",
        signing_secret: signing_secret
      )
    end
    let(:state) { ChatSDK::State::Memory.new }

    before do
      multi_adapter.set_state(state)
      # Clear any thread-local client from previous tests
      Thread.current[:chat_sdk_slack_client] = nil
    end

    after do
      Thread.current[:chat_sdk_slack_client] = nil
    end

    describe "#initialize" do
      it "accepts client_id + client_secret without bot_token" do
        adapter = described_class.new(
          client_id: "cid",
          client_secret: "csec",
          signing_secret: signing_secret
        )
        expect(adapter.name).to eq(:slack)
      end

      it "raises ConfigurationError without bot_token or client_id" do
        expect {
          described_class.new(signing_secret: signing_secret)
        }.to raise_error(ChatSDK::ConfigurationError, /bot_token or client_id required/)
      end
    end

    describe "#set_state" do
      it "injects the state store" do
        adapter = described_class.new(
          client_id: "cid",
          client_secret: "csec",
          signing_secret: signing_secret
        )
        adapter.set_state(state)
        # Should be able to set/get installations now
        adapter.set_installation("T001", bot_token: "xoxb-test")
        expect(adapter.get_installation("T001")).to include("bot_token" => "xoxb-test")
      end
    end

    describe "#set_installation" do
      it "stores installation data in state" do
        multi_adapter.set_installation("T001",
          bot_token: "xoxb-team1",
          bot_user_id: "U_BOT1",
          team_name: "Team One")

        stored = state.get("slack:installation:T001")
        expect(stored).to eq({
          "bot_token" => "xoxb-team1",
          "bot_user_id" => "U_BOT1",
          "team_name" => "Team One"
        })
      end

      it "raises ConfigurationError without state" do
        adapter = described_class.new(
          client_id: "cid",
          client_secret: "csec",
          signing_secret: signing_secret
        )
        expect {
          adapter.set_installation("T001", bot_token: "xoxb-test")
        }.to raise_error(ChatSDK::ConfigurationError, /requires state/)
      end
    end

    describe "#get_installation" do
      it "retrieves stored installation" do
        multi_adapter.set_installation("T001",
          bot_token: "xoxb-team1",
          bot_user_id: "U_BOT1",
          team_name: "Team One")

        result = multi_adapter.get_installation("T001")
        expect(result["bot_token"]).to eq("xoxb-team1")
        expect(result["bot_user_id"]).to eq("U_BOT1")
        expect(result["team_name"]).to eq("Team One")
      end

      it "returns nil for unknown team" do
        expect(multi_adapter.get_installation("T_UNKNOWN")).to be_nil
      end

      it "returns nil without state" do
        adapter = described_class.new(
          client_id: "cid",
          client_secret: "csec",
          signing_secret: signing_secret
        )
        expect(adapter.get_installation("T001")).to be_nil
      end
    end

    describe "#delete_installation" do
      it "removes installation from state" do
        multi_adapter.set_installation("T001", bot_token: "xoxb-team1")
        multi_adapter.delete_installation("T001")

        expect(multi_adapter.get_installation("T001")).to be_nil
      end
    end

    describe "#handle_oauth_callback" do
      it "exchanges code and stores installation" do
        temp_client = instance_double(::Slack::Web::Client)
        allow(::Slack::Web::Client).to receive(:new).with(no_args).and_return(temp_client)
        allow(temp_client).to receive(:oauth_v2_access).with(
          client_id: "test-client-id",
          client_secret: "test-client-secret",
          code: "oauth-code-123"
        ).and_return({
          "ok" => true,
          "access_token" => "xoxb-new-team-token",
          "bot_user_id" => "U_NEW_BOT",
          "team" => {"id" => "T_NEW", "name" => "New Team"}
        })

        result = multi_adapter.handle_oauth_callback(code: "oauth-code-123")

        expect(result[:team_id]).to eq("T_NEW")
        expect(result[:installation]["bot_token"]).to eq("xoxb-new-team-token")
        expect(result[:installation]["bot_user_id"]).to eq("U_NEW_BOT")
        expect(result[:installation]["team_name"]).to eq("New Team")

        # Verify it was stored
        stored = multi_adapter.get_installation("T_NEW")
        expect(stored["bot_token"]).to eq("xoxb-new-team-token")
      end

      it "raises ConfigurationError without client_id" do
        adapter = described_class.new(
          bot_token: bot_token,
          signing_secret: signing_secret
        )
        expect {
          adapter.handle_oauth_callback(code: "some-code")
        }.to raise_error(ChatSDK::ConfigurationError, /client_id required/)
      end

      it "passes redirect_uri when provided" do
        temp_client = instance_double(::Slack::Web::Client)
        allow(::Slack::Web::Client).to receive(:new).with(no_args).and_return(temp_client)
        allow(temp_client).to receive(:oauth_v2_access).with(
          client_id: "test-client-id",
          client_secret: "test-client-secret",
          code: "oauth-code-456",
          redirect_uri: "https://example.com/callback"
        ).and_return({
          "ok" => true,
          "access_token" => "xoxb-redir-token",
          "bot_user_id" => "U_REDIR",
          "team" => {"id" => "T_REDIR", "name" => "Redir Team"}
        })

        result = multi_adapter.handle_oauth_callback(
          code: "oauth-code-456",
          redirect_uri: "https://example.com/callback"
        )
        expect(result[:team_id]).to eq("T_REDIR")
      end
    end

    describe "per-webhook token resolution" do
      def build_request(body, content_type: "application/json")
        env = Rack::MockRequest.env_for(
          "/slack/events",
          :method => "POST",
          :input => body,
          "CONTENT_TYPE" => content_type
        )
        Rack::Request.new(env)
      end

      it "resolves team client from event_callback payload" do
        multi_adapter.set_installation("T_MULTI",
          bot_token: "xoxb-multi-token",
          bot_user_id: "U_MULTI_BOT")

        payload = {
          "type" => "event_callback",
          "team_id" => "T_MULTI",
          "event" => {
            "type" => "app_mention",
            "user" => "U123",
            "text" => "<@B456> hello",
            "ts" => "1234567890.123456",
            "channel" => "C789"
          }
        }
        request = build_request(JSON.generate(payload))
        events = multi_adapter.parse_events(request)

        expect(events.size).to eq(1)
        expect(multi_adapter.client).to be_a(::Slack::Web::Client)
        expect(multi_adapter.client.token).to eq("xoxb-multi-token")
      end

      it "resolves team client from interactive payload with team.id" do
        multi_adapter.set_installation("T_INTER",
          bot_token: "xoxb-inter-token")

        payload = {
          "type" => "block_actions",
          "team" => {"id" => "T_INTER"},
          "user" => {"id" => "U123", "name" => "testuser"},
          "channel" => {"id" => "C789"},
          "message" => {"ts" => "1234567890.123456"},
          "trigger_id" => "T999",
          "actions" => [
            {"action_id" => "btn:ok", "value" => "clicked"}
          ]
        }
        request = build_request(JSON.generate(payload))
        events = multi_adapter.parse_events(request)

        expect(events.size).to eq(1)
        expect(multi_adapter.client.token).to eq("xoxb-inter-token")
      end

      it "does not set thread client in single-workspace mode" do
        payload = {
          "type" => "event_callback",
          "team_id" => "T001",
          "event" => {
            "type" => "app_mention",
            "user" => "U123",
            "text" => "hello",
            "ts" => "1234567890.123456",
            "channel" => "C789"
          }
        }
        request = build_request(JSON.generate(payload))
        subject.parse_events(request)

        # Thread-local should not be set in single-workspace mode
        expect(Thread.current[:chat_sdk_slack_client]).to be_nil
      end
    end

    describe "#client in multi-workspace mode" do
      it "returns nil when no team client is resolved and no bot_token" do
        Thread.current[:chat_sdk_slack_client] = nil
        expect(multi_adapter.client).to be_nil
      end

      it "returns thread-local client when set" do
        team_client = ::Slack::Web::Client.new(token: "xoxb-thread-local")
        Thread.current[:chat_sdk_slack_client] = team_client

        expect(multi_adapter.client).to eq(team_client)
        expect(multi_adapter.client.token).to eq("xoxb-thread-local")
      end
    end
  end

  describe "#update_modal" do
    it "calls views_update with rendered modal" do
      modal = ChatSDK::Modals::Builder.new(
        title: "Edit Incident",
        callback_id: "edit_form"
      ) do
        text_input id: "title", label: "Title"
      end.build

      allow(subject.client).to receive(:views_update)
        .and_return({"ok" => true})

      subject.update_modal(view_id: "V123ABC", modal: modal)

      expect(subject.client).to have_received(:views_update) do |args|
        expect(args[:view_id]).to eq("V123ABC")
        expect(args[:view][:type]).to eq("modal")
        expect(args[:view][:callback_id]).to eq("edit_form")
      end
    end
  end

  describe "#send_to_response_url" do
    it "POSTs message payload to the response URL" do
      stub_request = nil
      allow(Faraday).to receive(:post).and_yield(
        double("request").tap do |req|
          allow(req).to receive(:headers).and_return({})
          allow(req).to receive(:body=) { |b| stub_request = b }
        end
      ).and_return(double("response", status: 200))

      subject.send_to_response_url(
        response_url: "https://hooks.slack.com/actions/T123/456/respond",
        message: "Hello from response URL"
      )

      expect(Faraday).to have_received(:post)
        .with("https://hooks.slack.com/actions/T123/456/respond")
      parsed = JSON.parse(stub_request)
      expect(parsed["text"]).to eq("Hello from response URL")
    end

    it "sends card blocks when message has a card" do
      stub_request = nil
      allow(Faraday).to receive(:post).and_yield(
        double("request").tap do |req|
          allow(req).to receive(:headers).and_return({})
          allow(req).to receive(:body=) { |b| stub_request = b }
        end
      ).and_return(double("response", status: 200))

      card = ChatSDK.card { text "Card content" }
      msg = ChatSDK::PostableMessage.new(card: card)

      subject.send_to_response_url(
        response_url: "https://hooks.slack.com/actions/T123/456/respond",
        message: msg
      )

      parsed = JSON.parse(stub_request)
      expect(parsed["blocks"]).to be_an(Array)
      expect(parsed["blocks"].first).to include("type" => "section")
    end
  end

  describe "#fetch_thread" do
    it "returns the channel info from conversations_info" do
      channel_data = {
        "id" => "C789",
        "name" => "general",
        "is_channel" => true
      }
      allow(subject.client).to receive(:conversations_info)
        .with(channel: "C789")
        .and_return({"ok" => true, "channel" => channel_data})

      result = subject.fetch_thread(channel_id: "C789")

      expect(result).to eq(channel_data)
      expect(result["id"]).to eq("C789")
      expect(result["name"]).to eq("general")
    end

    it "accepts an optional thread_id parameter" do
      channel_data = {"id" => "C789", "name" => "general"}
      allow(subject.client).to receive(:conversations_info)
        .with(channel: "C789")
        .and_return({"ok" => true, "channel" => channel_data})

      result = subject.fetch_thread(channel_id: "C789", thread_id: "1234567890.123456")

      expect(result).to eq(channel_data)
    end
  end

  describe "#stop_socket_mode" do
    it "stops the socket mode connection" do
      socket_double = instance_double(ChatSDK::Slack::SocketMode)
      allow(ChatSDK::Slack::SocketMode).to receive(:new)
        .with(app_token: "xapp-test-token", bot_client: subject.client)
        .and_return(socket_double)
      allow(socket_double).to receive(:start)
      allow(socket_double).to receive(:stop)

      subject.start_socket_mode(app_token: "xapp-test-token") { |_| }
      subject.stop_socket_mode

      expect(socket_double).to have_received(:stop)
    end

    it "does nothing when socket mode was never started" do
      expect { subject.stop_socket_mode }.not_to raise_error
    end
  end

  describe "#start_socket_mode" do
    it "raises ConfigurationError without app_token" do
      expect { subject.start_socket_mode(app_token: nil) {} }
        .to raise_error(ChatSDK::ConfigurationError, /app_token required/)
    end

    it "raises ConfigurationError without app_token when ENV is empty" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SLACK_APP_TOKEN").and_return(nil)

      expect { subject.start_socket_mode {} }
        .to raise_error(ChatSDK::ConfigurationError, /app_token required/)
    end

    it "delegates to SocketMode with the given app_token" do
      socket_double = instance_double(ChatSDK::Slack::SocketMode)
      allow(ChatSDK::Slack::SocketMode).to receive(:new)
        .with(app_token: "xapp-test-token", bot_client: subject.client)
        .and_return(socket_double)

      block = proc { |_event| }
      allow(socket_double).to receive(:start)

      subject.start_socket_mode(app_token: "xapp-test-token", &block)

      expect(socket_double).to have_received(:start)
    end
  end

  describe ChatSDK::Slack::BlockKitRenderer do
    let(:renderer) { described_class.new }

    describe "#render" do
      it "renders a text node as a section block" do
        node = ChatSDK::Cards::Node.new(:text, attributes: {content: "Hello world"})
        result = renderer.render(node)
        expect(result).to eq([{type: "section", text: {type: "mrkdwn", text: "Hello world"}}])
      end

      it "renders a card with multiple children" do
        card = ChatSDK.card do
          text "Line 1"
          divider
          text "Line 2"
        end
        result = renderer.render(card)

        expect(result.size).to eq(3)
        expect(result[0][:type]).to eq("section")
        expect(result[0][:text][:text]).to eq("Line 1")
        expect(result[1][:type]).to eq("divider")
        expect(result[2][:type]).to eq("section")
        expect(result[2][:text][:text]).to eq("Line 2")
      end

      it "renders fields" do
        card = ChatSDK.card do
          fields do
            field "Status", "Active"
            field "Severity", "SEV1"
          end
        end
        result = renderer.render(card)

        expect(result.size).to eq(1)
        expect(result[0][:type]).to eq("section")
        expect(result[0][:fields].size).to eq(2)
        expect(result[0][:fields][0]).to eq({type: "mrkdwn", text: "*Status*\nActive"})
      end

      it "renders an image" do
        card = ChatSDK.card do
          image url: "https://example.com/img.png", alt: "Screenshot"
        end
        result = renderer.render(card)

        expect(result.size).to eq(1)
        expect(result[0][:type]).to eq("image")
        expect(result[0][:image_url]).to eq("https://example.com/img.png")
        expect(result[0][:alt_text]).to eq("Screenshot")
      end

      it "renders actions with buttons" do
        card = ChatSDK.card do
          actions do
            button "Approve", id: "btn:approve", style: :primary, value: "yes"
            button "Reject", id: "btn:reject", style: :danger
            link_button "View", url: "https://example.com"
          end
        end
        result = renderer.render(card)

        expect(result.size).to eq(1)
        actions_block = result[0]
        expect(actions_block[:type]).to eq("actions")
        expect(actions_block[:elements].size).to eq(3)

        approve_btn = actions_block[:elements][0]
        expect(approve_btn[:type]).to eq("button")
        expect(approve_btn[:text]).to eq({type: "plain_text", text: "Approve"})
        expect(approve_btn[:action_id]).to eq("btn:approve")
        expect(approve_btn[:style]).to eq("primary")
        expect(approve_btn[:value]).to eq("yes")

        reject_btn = actions_block[:elements][1]
        expect(reject_btn[:style]).to eq("danger")

        link_btn = actions_block[:elements][2]
        expect(link_btn[:url]).to eq("https://example.com")
      end

      it "renders a select menu" do
        card = ChatSDK.card do
          actions do
            select id: "severity_select", placeholder: "Choose severity" do
              option "SEV1", value: "sev1"
              option "SEV2", value: "sev2", description: "Less critical"
            end
          end
        end
        result = renderer.render(card)

        select_el = result[0][:elements][0]
        expect(select_el[:type]).to eq("static_select")
        expect(select_el[:action_id]).to eq("severity_select")
        expect(select_el[:placeholder]).to eq({type: "plain_text", text: "Choose severity"})
        expect(select_el[:options].size).to eq(2)
        expect(select_el[:options][1][:description]).to eq({type: "plain_text", text: "Less critical"})
      end
    end
  end

  describe ChatSDK::Slack::ModalRenderer do
    let(:renderer) { described_class.new }

    describe "#render" do
      it "renders a modal with text input" do
        modal = ChatSDK::Modals::Builder.new(
          title: "Create Incident",
          submit_label: "Submit",
          callback_id: "incident_form"
        ) do
          text_input id: "title", label: "Title", placeholder: "Enter title"
          text_input id: "description", label: "Description", multiline: true, optional: true
        end.build

        result = renderer.render(modal)

        expect(result[:type]).to eq("modal")
        expect(result[:title]).to eq({type: "plain_text", text: "Create Incident"})
        expect(result[:submit]).to eq({type: "plain_text", text: "Submit"})
        expect(result[:callback_id]).to eq("incident_form")
        expect(result[:blocks].size).to eq(2)

        title_block = result[:blocks][0]
        expect(title_block[:type]).to eq("input")
        expect(title_block[:block_id]).to eq("title")
        expect(title_block[:element][:type]).to eq("plain_text_input")
        expect(title_block[:element][:multiline]).to be(false)
        expect(title_block[:element][:placeholder]).to eq({type: "plain_text", text: "Enter title"})

        desc_block = result[:blocks][1]
        expect(desc_block[:element][:multiline]).to be(true)
        expect(desc_block[:optional]).to be(true)
      end

      it "renders a modal with select input" do
        modal = ChatSDK::Modals::Builder.new(title: "Severity") do
          select_input id: "sev", label: "Severity", placeholder: "Pick one" do
            option "SEV1", value: "sev1"
            option "SEV2", value: "sev2"
          end
        end.build

        result = renderer.render(modal)

        select_block = result[:blocks][0]
        expect(select_block[:element][:type]).to eq("static_select")
        expect(select_block[:element][:options].size).to eq(2)
      end
    end
  end
end
