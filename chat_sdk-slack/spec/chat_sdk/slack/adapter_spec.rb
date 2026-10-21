# frozen_string_literal: true

require_relative "../../spec_helper"
require "openssl"
require "rack"

RSpec.describe ChatSDK::Slack::Adapter do
  subject { described_class.new(bot_token: bot_token, signing_secret: signing_secret, bot_user_id: "B456") }

  let(:bot_token) { "xoxb-test-token-12345" }
  let(:signing_secret) { "test_signing_secret_abc123" }

  it_behaves_like "a chat_sdk platform adapter"

  describe "#initialize" do
    it "raises ConfigurationError without bot_token or client_id" do
      expect { described_class.new(bot_token: nil, signing_secret: signing_secret) }
        .to raise_error(ChatSDK::ConfigurationError, /Slack bot_token, client_id or installation_provider required/)
    end

    it "raises ConfigurationError without signing_secret" do
      expect { described_class.new(bot_token: bot_token, signing_secret: nil) }
        .to raise_error(ChatSDK::ConfigurationError, /signing_secret or webhook_verifier required/)
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

    it "isolates request contexts between adapter instances" do
      other_adapter = described_class.new(bot_token: "xoxb-other", signing_secret: signing_secret)

      other_adapter.with_bot_token("xoxb-temporary") do
        expect(subject.client.token).to eq(bot_token)
      end
    end

    it "configures an egress proxy" do
      adapter = described_class.new(
        bot_token: bot_token,
        signing_secret: signing_secret,
        proxy: "http://proxy.internal:8080"
      )

      expect(adapter.client.proxy).to eq("http://proxy.internal:8080")
    end

    it "resolves callable bot tokens for every client access and caches by token" do
      tokens = %w[xoxb-first xoxb-second xoxb-third]
      resolver = double("token resolver")
      allow(resolver).to receive(:call) { tokens.shift }
      adapter = described_class.new(bot_token: resolver, signing_secret: signing_secret)

      clients = 3.times.map { adapter.client }

      expect(clients.map(&:token)).to eq(%w[xoxb-first xoxb-second xoxb-third])
      expect(clients.uniq.size).to eq(3)
      expect(resolver).to have_received(:call).exactly(3).times
    end

    it "raises when a callable bot token resolver returns nil or an empty token" do
      [nil, ""].each do |token|
        adapter = described_class.new(bot_token: -> { token }, signing_secret: signing_secret)

        expect { adapter.client }
          .to raise_error(ChatSDK::ConfigurationError, "Slack bot_token resolver returned no token")
      end
    end

    it "propagates callable bot token resolver errors" do
      adapter = described_class.new(
        bot_token: -> { raise "resolver error" },
        signing_secret: signing_secret
      )

      expect { adapter.client }.to raise_error("resolver error")
    end

    it "uses callable bot tokens for single-workspace auth.test and caches the result" do
      resolver = double("token resolver")
      allow(resolver).to receive(:call).and_return("xoxb-callable")
      adapter = described_class.new(bot_token: resolver, signing_secret: signing_secret)
      auth_client = adapter.client
      allow(auth_client).to receive(:auth_test).and_return({"user_id" => "B_CALLABLE"})
      payload = {
        "type" => "event_callback",
        "event" => {
          "type" => "message",
          "user" => "U123",
          "text" => "hello",
          "ts" => "1234567890.123456",
          "channel" => "C789",
          "channel_type" => "channel"
        }
      }
      request_env = Rack::MockRequest.env_for(
        "/slack/events",
        method: "POST",
        input: JSON.generate(payload)
      )
      request_env["CONTENT_TYPE"] = "application/json"
      request = Rack::Request.new(request_env)

      2.times { adapter.parse_events(request) }

      expect(auth_client).to have_received(:auth_test).once
      expect(resolver).to have_received(:call).at_least(:once)
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

    it "accepts a request through webhook_verifier without Slack signature headers" do
      body = '{"type":"event_callback"}'
      verifier = proc do |request, verified_body|
        expect(request).to be_a(Rack::Request)
        expect(verified_body).to eq(body)
        true
      end
      adapter = described_class.new(bot_token: bot_token, webhook_verifier: verifier)
      request = Rack::Request.new(Rack::MockRequest.env_for("/slack/events", method: "POST", input: body))

      expect(adapter.verify_request!(request)).to be(true)
    end

    it "gives webhook_verifier precedence over the signing secret environment variable" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SLACK_SIGNING_SECRET").and_return("ignored-secret")
      verifier = proc { |_request, _body| true }
      adapter = described_class.new(bot_token: bot_token, signing_secret: signing_secret, webhook_verifier: verifier)
      request = Rack::Request.new(Rack::MockRequest.env_for("/slack/events", method: "POST", input: "{}"))

      expect(adapter.verify_request!(request)).to be(true)
    end

    it "rejects falsey verifier results" do
      [false, nil].each do |result|
        adapter = described_class.new(bot_token: bot_token, webhook_verifier: ->(_request, _body) { result })
        request = Rack::Request.new(Rack::MockRequest.env_for("/slack/events", method: "POST", input: "{}"))

        expect { adapter.verify_request!(request) }
          .to raise_error(ChatSDK::SignatureVerificationError, /verifier rejected/)
      end
    end

    it "wraps exceptions raised by webhook_verifier" do
      adapter = described_class.new(
        bot_token: bot_token,
        webhook_verifier: ->(_request, _body) { raise "verifier error" }
      )
      request = Rack::Request.new(Rack::MockRequest.env_for("/slack/events", method: "POST", input: "{}"))

      expect { adapter.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /verifier failed: verifier error/)
    end

    it "uses a String verifier result for subsequent challenge parsing" do
      replacement = '{"type":"url_verification","challenge":"verified-challenge"}'
      adapter = described_class.new(bot_token: bot_token, webhook_verifier: ->(_request, _body) { replacement })
      request = Rack::Request.new(
        Rack::MockRequest.env_for("/slack/events", method: "POST", input: '{"type":"invalid"}')
      )

      adapter.verify_request!(request)

      expect(adapter.ack_response(request)).to eq([200, {"content-type" => "text/plain"}, ["verified-challenge"]])
    end

    it "rejects a non-callable verifier at initialization" do
      expect {
        described_class.new(bot_token: bot_token, webhook_verifier: "not-callable")
      }.to raise_error(ChatSDK::ConfigurationError, /webhook_verifier must be callable/)
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

  describe "Slack message enhancements" do
    def build_event_request(payload)
      env = Rack::MockRequest.env_for(
        "/slack/events",
        :method => "POST",
        :input => JSON.generate(payload),
        "CONTENT_TYPE" => "application/json"
      )
      Rack::Request.new(env)
    end

    def slack_message_payload(type:, text:, blocks: nil, team_id: nil)
      event = {
        "type" => type,
        "user" => "U123",
        "text" => text,
        "ts" => "1234567890.123456",
        "channel" => "C789",
        "channel_type" => "channel"
      }
      event["blocks"] = blocks if blocks
      payload = {"type" => "event_callback", "event" => event}
      payload["team_id"] = team_id if team_id
      payload
    end

    it "classifies a bot mention from mrkdwn for app_mention and message events" do
      adapter = described_class.new(bot_token: bot_token, signing_secret: signing_secret, bot_user_id: "B456")
      %w[app_mention message].each do |type|
        event = adapter.parse_events(build_event_request(slack_message_payload(type: type, text: "hello <@B456>"))).first
        expect(event.message.is_mention).to be(true)
      end
    end

    it "classifies labeled mentions of the bot" do
      adapter = described_class.new(bot_token: bot_token, signing_secret: signing_secret, bot_user_id: "B456")
      event = adapter.parse_events(
        build_event_request(slack_message_payload(type: "message", text: "hello <@B456|helper>"))
      ).first

      expect(event.message.is_mention).to be(true)
    end

    it "uses the configured bot user ID environment variable" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SLACK_BOT_USER_ID").and_return("B_ENV")
      adapter = described_class.new(bot_token: bot_token, signing_secret: signing_secret)
      event = adapter.parse_events(build_event_request(slack_message_payload(type: "message", text: "<@B_ENV>"))).first

      expect(event.message.is_mention).to be(true)
    end

    it "ignores bot tokens that appear only inside code" do
      adapter = described_class.new(bot_token: bot_token, signing_secret: signing_secret, bot_user_id: "B456")
      event = adapter.parse_events(build_event_request(slack_message_payload(type: "message", text: "`<@B456>`"))).first

      expect(event.message.is_mention).to be(false)
    end

    it "marks inspected messages without the bot mention as false" do
      adapter = described_class.new(bot_token: bot_token, signing_secret: signing_secret, bot_user_id: "B456")
      event = adapter.parse_events(build_event_request(slack_message_payload(type: "message", text: "hello"))).first

      expect(event.message.is_mention).to be(false)
    end

    it "classifies app_mention without resolving an unknown bot user ID" do
      adapter = described_class.new(bot_token: bot_token, signing_secret: signing_secret)
      allow(adapter.client).to receive(:auth_test).and_return({})
      app_mention = adapter.parse_events(build_event_request(slack_message_payload(type: "app_mention", text: "hello"))).first

      expect(app_mention.message.is_mention).to be(true)
      expect(adapter.client).not_to have_received(:auth_test)

      message = adapter.parse_events(build_event_request(slack_message_payload(type: "message", text: "hello"))).first

      expect(message.message.is_mention).to be_nil
      expect(adapter.client).to have_received(:auth_test).once
    end

    it "retries auth.test after a lookup error" do
      adapter = described_class.new(bot_token: bot_token, signing_secret: signing_secret)
      auth_test_calls = 0
      allow(adapter.client).to receive(:auth_test) do
        auth_test_calls += 1
        raise ::Slack::Web::Api::Errors::SlackError, "temporary error" if auth_test_calls == 1

        {"user_id" => "B456"}
      end
      request = build_event_request(slack_message_payload(type: "message", text: "hello"))

      first = adapter.parse_events(request).first
      second = adapter.parse_events(request).first

      expect(first.message.is_mention).to be_nil
      expect(second.message.is_mention).to be(false)
      expect(auth_test_calls).to eq(2)
    end

    it "classifies rich-text user elements outside preformatted blocks" do
      adapter = described_class.new(bot_token: bot_token, signing_secret: signing_secret, bot_user_id: "B456")
      blocks = [{"type" => "rich_text", "elements" => [
        {"type" => "rich_text_section", "elements" => [{"type" => "user", "user_id" => "B456"}]}
      ]}]
      event = adapter.parse_events(build_event_request(slack_message_payload(type: "message", text: "", blocks: blocks))).first

      expect(event.message.is_mention).to be(true)
    end

    it "does not classify rich-text users inside preformatted blocks as mentions" do
      adapter = described_class.new(bot_token: bot_token, signing_secret: signing_secret, bot_user_id: "B456")
      blocks = [{"type" => "rich_text", "elements" => [
        {"type" => "rich_text_preformatted", "elements" => [{"type" => "user", "user_id" => "B456"}]}
      ]}]
      event = adapter.parse_events(build_event_request(slack_message_payload(type: "message", text: "", blocks: blocks))).first

      expect(event.message.is_mention).to be(false)
    end

    it "resolves auth.test once per client when the bot user ID is not configured" do
      adapter = described_class.new(bot_token: bot_token, signing_secret: signing_secret)
      allow(adapter.client).to receive(:auth_test).and_return({"user_id" => "B456"})
      request = build_event_request(slack_message_payload(type: "message", text: "<@B456>"))

      2.times { adapter.parse_events(request) }

      expect(adapter.client).to have_received(:auth_test).once
    end

    it "resolves and caches bot user IDs separately for workspaces without configured IDs" do
      adapter = described_class.new(
        client_id: "client",
        client_secret: "secret",
        signing_secret: signing_secret
      )
      adapter.set_state(ChatSDK::State::Memory.new)
      adapter.set_installation("T1", bot_token: "xoxb-team-1")
      adapter.set_installation("T2", bot_token: "xoxb-team-2")
      auth_client_1 = instance_double(::Slack::Web::Client)
      auth_client_2 = instance_double(::Slack::Web::Client)
      allow(adapter).to receive(:build_client).with(token: "xoxb-team-1").and_return(auth_client_1)
      allow(adapter).to receive(:build_client).with(token: "xoxb-team-2").and_return(auth_client_2)
      allow(auth_client_1).to receive(:auth_test).and_return({"user_id" => "B_TEAM_1"})
      allow(auth_client_2).to receive(:auth_test).and_return({"user_id" => "B_TEAM_2"})
      event_for = lambda do |team_id|
        ChatSDK::Events::Mention.new(
          message: ChatSDK::Message.new(
            id: "M1",
            text: "",
            author: ChatSDK::Author.new(id: "U1", name: "user", platform: :slack),
            thread_id: "T1",
            channel_id: "C1",
            platform: :slack
          ),
          thread_id: "T1",
          channel_id: "C1",
          platform: :slack,
          adapter_name: :slack,
          raw: {"team_id" => team_id}
        )
      end

      expect(adapter.send(:resolve_bot_user_id, event_for.call("T1"))).to eq("B_TEAM_1")
      expect(adapter.send(:resolve_bot_user_id, event_for.call("T1"))).to eq("B_TEAM_1")
      expect(adapter.send(:resolve_bot_user_id, event_for.call("T2"))).to eq("B_TEAM_2")
      expect(auth_client_1).to have_received(:auth_test).once
      expect(auth_client_2).to have_received(:auth_test).once
    end

    it "evicts cached bot user IDs when installations change or are deleted" do
      adapter = described_class.new(
        client_id: "client",
        client_secret: "secret",
        signing_secret: signing_secret
      )
      adapter.set_state(ChatSDK::State::Memory.new)
      adapter.set_installation("T1", bot_token: "xoxb-team-1")
      auth_client_1 = instance_double(::Slack::Web::Client)
      auth_client_2 = instance_double(::Slack::Web::Client)
      auth_client_3 = instance_double(::Slack::Web::Client)
      allow(adapter).to receive(:build_client).with(token: "xoxb-team-1").and_return(auth_client_1)
      allow(adapter).to receive(:build_client).with(token: "xoxb-team-1-reinstalled").and_return(auth_client_2)
      allow(adapter).to receive(:build_client).with(token: "xoxb-team-1-after-delete").and_return(auth_client_3)
      allow(auth_client_1).to receive(:auth_test).and_return({"user_id" => "B_TEAM_1"})
      allow(auth_client_2).to receive(:auth_test).and_return({"user_id" => "B_TEAM_2"})
      allow(auth_client_3).to receive(:auth_test).and_return({"user_id" => "B_TEAM_3"})
      event = ChatSDK::Events::Mention.new(
        message: ChatSDK::Message.new(
          id: "M1",
          text: "",
          author: ChatSDK::Author.new(id: "U1", name: "user", platform: :slack),
          thread_id: "T1",
          channel_id: "C1",
          platform: :slack
        ),
        thread_id: "T1",
        channel_id: "C1",
        platform: :slack,
        adapter_name: :slack,
        raw: {"team_id" => "T1"}
      )

      expect(adapter.send(:resolve_bot_user_id, event)).to eq("B_TEAM_1")
      adapter.set_installation("T1", bot_token: "xoxb-team-1-reinstalled")
      expect(adapter.send(:resolve_bot_user_id, event)).to eq("B_TEAM_2")
      adapter.delete_installation("T1")
      expect(adapter.send(:resolve_bot_user_id, event)).to be_nil
      adapter.set_installation("T1", bot_token: "xoxb-team-1-after-delete")
      expect(adapter.send(:resolve_bot_user_id, event)).to eq("B_TEAM_3")
    end

    it "normalizes Slack mentions while preserving code spans" do
      adapter = described_class.new(bot_token: bot_token, signing_secret: signing_secret, bot_user_id: "B456")
      text = "<!here> <!channel> <!everyone> <!subteam^S1|@team> <mailto:a@b|email> <tel:123|call> `<!here>`"
      event = adapter.parse_events(build_event_request(slack_message_payload(type: "message", text: text))).first

      expect(event.message.text).to eq("@here @channel @everyone @team email call `<!here>`")
    end

    it "scopes multi-workspace events by team ID" do
      adapter = described_class.new(client_id: "client", client_secret: "secret", signing_secret: signing_secret)
      [
        [{"team_id" => "T1"}, "T1"],
        [{"team" => {"id" => "T2"}}, "T2"],
        [{"event" => {"team" => "T3"}}, "T3"]
      ].each do |raw, team_id|
        event = ChatSDK::Events::Mention.new(
          message: ChatSDK::Message.new(id: "M1", text: "", author: ChatSDK::Author.new(id: "U1", name: "user", platform: :slack),
            thread_id: "T1", channel_id: "C1", platform: :slack),
          thread_id: "T1", channel_id: "C1", platform: :slack, adapter_name: :slack,
          raw: raw
        )

        expect(adapter.concurrency_scope(event)).to eq(team_id)
      end
      single_workspace_event = ChatSDK::Events::Mention.new(
        message: ChatSDK::Message.new(id: "M1", text: "", author: ChatSDK::Author.new(id: "U1", name: "user", platform: :slack),
          thread_id: "T1", channel_id: "C1", platform: :slack),
        thread_id: "T1", channel_id: "C1", platform: :slack, adapter_name: :slack,
        raw: {"team_id" => "T1"}
      )
      expect(subject.concurrency_scope(single_workspace_event)).to be_nil
    end

    it "uses the workspace installation bot user ID" do
      adapter = described_class.new(
        client_id: "client",
        client_secret: "secret",
        signing_secret: signing_secret
      )
      adapter.set_state(ChatSDK::State::Memory.new)
      adapter.set_installation("T1", bot_token: "xoxb-workspace", bot_user_id: "B_WORKSPACE")
      event = adapter.parse_events(build_event_request(
        slack_message_payload(type: "message", text: "<@B_WORKSPACE>", team_id: "T1")
      )).first

      expect(event.message.is_mention).to be(true)
    end

    it "uploads files through files_upload_v2" do
      io = StringIO.new("contents")
      allow(subject.client).to receive(:files_upload_v2).and_return({"ok" => true})

      subject.upload_file(channel_id: "C1", io: io, filename: "report.txt", thread_id: "T1", comment: "Here")

      expect(subject.client).to have_received(:files_upload_v2).with(
        channel_id: "C1", filename: "report.txt", content: "contents", thread_ts: "T1", initial_comment: "Here"
      )
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
        }.to raise_error(ChatSDK::ConfigurationError, /Slack bot_token, client_id or installation_provider required/)
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

      it "stores Enterprise Grid organization installs under the enterprise ID" do
        temp_client = instance_double(::Slack::Web::Client)
        allow(::Slack::Web::Client).to receive(:new).with(no_args).and_return(temp_client)
        allow(temp_client).to receive(:oauth_v2_access).and_return({
          "ok" => true,
          "access_token" => "xoxb-enterprise",
          "bot_user_id" => "B_ENTERPRISE",
          "is_enterprise_install" => true,
          "enterprise" => {"id" => "E_ORG", "name" => "Organization"},
          "team" => nil
        })

        result = multi_adapter.handle_oauth_callback(code: "enterprise-code")

        expect(result).to include(
          team_id: "E_ORG",
          enterprise_id: "E_ORG",
          enterprise_install: true
        )
        expect(result[:installation]["team_name"]).to eq("Organization")
        expect(multi_adapter.get_installation("E_ORG")).to include(
          "enterprise_id" => "E_ORG",
          "is_enterprise_install" => true
        )
      end

      it "records enterprise metadata for a workspace install in Grid" do
        temp_client = instance_double(::Slack::Web::Client)
        allow(::Slack::Web::Client).to receive(:new).with(no_args).and_return(temp_client)
        allow(temp_client).to receive(:oauth_v2_access).and_return({
          "ok" => true,
          "access_token" => "xoxb-grid-workspace",
          "is_enterprise_install" => false,
          "enterprise" => {"id" => "E_GRID", "name" => "Grid"},
          "team" => {"id" => "T_GRID", "name" => "Grid Team"}
        })

        result = multi_adapter.handle_oauth_callback(code: "grid-code")

        expect(result).to include(team_id: "T_GRID", enterprise_id: "E_GRID", enterprise_install: false)
        expect(multi_adapter.get_installation("T_GRID")).to include(
          "enterprise_id" => "E_GRID",
          "is_enterprise_install" => false
        )
      end

      it "raises when an enterprise install is missing its enterprise ID" do
        temp_client = instance_double(::Slack::Web::Client)
        allow(::Slack::Web::Client).to receive(:new).with(no_args).and_return(temp_client)
        allow(temp_client).to receive(:oauth_v2_access).and_return({
          "ok" => true,
          "access_token" => "xoxb-enterprise",
          "is_enterprise_install" => true,
          "enterprise" => {},
          "team" => nil
        })

        expect { multi_adapter.handle_oauth_callback(code: "missing-id") }
          .to raise_error(ChatSDK::ConfigurationError, /enterprise\.id/)
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

        expect(subject.client.token).to eq(bot_token)
      end
    end

    describe "#client in multi-workspace mode" do
      it "returns nil when no team client is resolved and no bot_token" do
        expect(multi_adapter.client).to be_nil
      end

      it "uses the token supplied by with_bot_token" do
        multi_adapter.with_bot_token("xoxb-thread-local", installation_id: "T001") do
          expect(multi_adapter.client.token).to eq("xoxb-thread-local")
        end

        expect(multi_adapter.client).to be_nil
      end
    end
  end

  describe "Slack installation providers" do
    let(:signing_secret) { "test_signing_secret_abc123" }

    def request_for(payload, content_type: "application/json")
      body = if content_type == "application/x-www-form-urlencoded"
        Rack::Utils.build_query(payload)
      else
        JSON.generate(payload)
      end
      env = Rack::MockRequest.env_for(
        "/slack/events",
        method: "POST",
        input: body
      )
      env["CONTENT_TYPE"] = content_type
      Rack::Request.new(env)
    end

    def installation_payload(team_id: "T_PROVIDER", text: "hello", event_type: "app_mention", extra: {})
      {
        "type" => "event_callback",
        "team_id" => team_id,
        **extra,
        "event" => {
          "type" => event_type,
          "user" => "U123",
          "text" => text,
          "ts" => "1234567890.123456",
          "channel" => "C789",
          "channel_type" => "channel"
        }
      }
    end

    it "resolves workspace event installations using the provider token" do
      provider = double("installation provider")
      allow(provider).to receive(:get_installation)
        .with("T_PROVIDER", enterprise_install: false)
        .and_return({"bot_token" => "xoxb-provider", "bot_user_id" => "B_PROVIDER"})
      adapter = described_class.new(installation_provider: provider, signing_secret: signing_secret)

      events = adapter.parse_events(request_for(installation_payload))

      expect(events.size).to eq(1)
      expect(adapter.client.token).to eq("xoxb-provider")
      expect(provider).to have_received(:get_installation).with("T_PROVIDER", enterprise_install: false)
    end

    it "resolves Enterprise Grid events with their enterprise ID" do
      provider = double("installation provider")
      allow(provider).to receive(:get_installation)
        .with("E_PROVIDER", enterprise_install: true)
        .and_return({"bot_token" => "xoxb-enterprise-provider"})
      payload = installation_payload(
        team_id: "T_ENTERPRISE",
        extra: {
          "enterprise_id" => "E_TOP_LEVEL",
          "authorizations" => [{
            "team_id" => "T_PROVIDER",
            "enterprise_id" => "E_PROVIDER",
            "is_enterprise_install" => true
          }]
        }
      )
      adapter = described_class.new(installation_provider: provider, signing_secret: signing_secret)

      expect(adapter.parse_events(request_for(payload)).size).to eq(1)
      expect(adapter.client.token).to eq("xoxb-enterprise-provider")
      expect(provider).to have_received(:get_installation).with("E_PROVIDER", enterprise_install: true)
    end

    it "prefers the first authorization over top-level event identifiers" do
      provider = double("installation provider")
      allow(provider).to receive(:get_installation)
        .with("T_AUTHORIZATION", enterprise_install: false)
        .and_return({"bot_token" => "xoxb-authorization"})
      payload = installation_payload(
        team_id: "T_TOP_LEVEL",
        extra: {
          "authorizations" => [{"team_id" => "T_AUTHORIZATION", "is_enterprise_install" => false}]
        }
      )
      adapter = described_class.new(installation_provider: provider, signing_secret: signing_secret)

      adapter.parse_events(request_for(payload))

      expect(adapter.client.token).to eq("xoxb-authorization")
    end

    it "does not fall back to state when the configured provider returns nil" do
      provider = double("installation provider", get_installation: nil)
      adapter = described_class.new(installation_provider: provider, signing_secret: signing_secret)
      adapter.set_state(ChatSDK::State::Memory.new)
      adapter.set_installation("T_PROVIDER", bot_token: "xoxb-state-token")

      expect(adapter.parse_events(request_for(installation_payload))).to eq([])
      expect(adapter.client).to be_nil
    end

    it "resolves slash command installations from form fields" do
      provider = double("installation provider")
      allow(provider).to receive(:get_installation)
        .with("T_SLASH", enterprise_install: false)
        .and_return({"bot_token" => "xoxb-slash"})
      payload = {
        "command" => "/help",
        "text" => "status",
        "team_id" => "T_SLASH",
        "user_id" => "U123",
        "channel_id" => "C789",
        "trigger_id" => "TRIGGER"
      }
      adapter = described_class.new(installation_provider: provider, signing_secret: signing_secret)

      events = adapter.parse_events(request_for(payload, content_type: "application/x-www-form-urlencoded"))

      expect(events.first).to be_a(ChatSDK::Events::SlashCommand)
      expect(adapter.client.token).to eq("xoxb-slash")
    end

    it "resolves Enterprise Grid slash command installations from enterprise_id" do
      provider = double("installation provider")
      allow(provider).to receive(:get_installation)
        .with("E_SLASH", enterprise_install: true)
        .and_return({"bot_token" => "xoxb-enterprise-slash"})
      payload = {
        "command" => "/help",
        "text" => "status",
        "team_id" => "T_SLASH",
        "enterprise_id" => "E_SLASH",
        "is_enterprise_install" => "true",
        "user_id" => "U123",
        "channel_id" => "C789",
        "trigger_id" => "TRIGGER"
      }
      adapter = described_class.new(installation_provider: provider, signing_secret: signing_secret)

      events = adapter.parse_events(request_for(payload, content_type: "application/x-www-form-urlencoded"))

      expect(events.first).to be_a(ChatSDK::Events::SlashCommand)
      expect(adapter.client.token).to eq("xoxb-enterprise-slash")
    end

    it "resolves interactive enterprise installations using enterprise.id" do
      provider = double("installation provider")
      allow(provider).to receive(:get_installation)
        .with("E_ACTION", enterprise_install: true)
        .and_return({"bot_token" => "xoxb-action"})
      payload = {
        "type" => "block_actions",
        "is_enterprise_install" => "true",
        "enterprise" => {"id" => "E_ACTION"},
        "enterprise_id" => "E_FALLBACK",
        "team" => {"id" => "T_ACTION"},
        "user" => {"id" => "U123", "name" => "user"},
        "channel" => {"id" => "C789"},
        "message" => {"ts" => "1234567890.123456"},
        "trigger_id" => "TRIGGER",
        "actions" => [{"action_id" => "action", "value" => "yes"}]
      }
      adapter = described_class.new(installation_provider: provider, signing_secret: signing_secret)

      expect(adapter.parse_events(request_for(payload)).first).to be_a(ChatSDK::Events::Action)
      expect(adapter.client.token).to eq("xoxb-action")
    end

    it "uses interactive enterprise_id and team_id when nested IDs are absent" do
      provider = double("installation provider")
      allow(provider).to receive(:get_installation)
        .with("E_ACTION_FALLBACK", enterprise_install: true)
        .and_return({"bot_token" => "xoxb-action-fallback"})
      payload = {
        "type" => "block_actions",
        "is_enterprise_install" => true,
        "enterprise" => {},
        "enterprise_id" => "E_ACTION_FALLBACK",
        "team" => {},
        "team_id" => "T_ACTION_FALLBACK",
        "user" => {"id" => "U123", "name" => "user"},
        "channel" => {"id" => "C789"},
        "message" => {"ts" => "1234567890.123456"},
        "trigger_id" => "TRIGGER",
        "actions" => [{"action_id" => "action", "value" => "yes"}]
      }
      adapter = described_class.new(installation_provider: provider, signing_secret: signing_secret)

      expect(adapter.parse_events(request_for(payload)).first).to be_a(ChatSDK::Events::Action)
      expect(adapter.client.token).to eq("xoxb-action-fallback")
    end

    it "uses interactive team_id when the nested team ID is absent" do
      provider = double("installation provider")
      allow(provider).to receive(:get_installation)
        .with("T_ACTION_FALLBACK", enterprise_install: false)
        .and_return({"bot_token" => "xoxb-team-action-fallback"})
      payload = {
        "type" => "block_actions",
        "team" => {},
        "team_id" => "T_ACTION_FALLBACK",
        "user" => {"id" => "U123", "name" => "user"},
        "channel" => {"id" => "C789"},
        "message" => {"ts" => "1234567890.123456"},
        "trigger_id" => "TRIGGER",
        "actions" => [{"action_id" => "action", "value" => "yes"}]
      }
      adapter = described_class.new(installation_provider: provider, signing_secret: signing_secret)

      expect(adapter.parse_events(request_for(payload)).first).to be_a(ChatSDK::Events::Action)
      expect(adapter.client.token).to eq("xoxb-team-action-fallback")
    end

    it "accepts a callable installation provider" do
      provider = double("callable provider")
      allow(provider).to receive(:call)
        .with("T_PROVIDER", enterprise_install: false)
        .and_return({bot_token: "xoxb-callable-provider"})
      adapter = described_class.new(installation_provider: provider, signing_secret: signing_secret)

      adapter.parse_events(request_for(installation_payload))

      expect(adapter.client.token).to eq("xoxb-callable-provider")
      expect(provider).to have_received(:call).with("T_PROVIDER", enterprise_install: false)
    end

    it "logs provider errors and drops events when there is no fallback token" do
      provider = double("installation provider")
      allow(provider).to receive(:get_installation).and_raise("provider failure")
      allow(ChatSDK::Log).to receive(:error)
      allow(ChatSDK::Log).to receive(:warn)
      adapter = described_class.new(installation_provider: provider, signing_secret: signing_secret)

      expect(adapter.parse_events(request_for(installation_payload))).to eq([])
      expect(ChatSDK::Log).to have_received(:error).with(/Could not resolve Slack installation T_PROVIDER/)
      expect(ChatSDK::Log).to have_received(:warn).with(/Dropping Slack event without a resolved installation/)
    end

    it "uses a static bot token as a fallback when a multi-workspace provider misses" do
      provider = double("installation provider", get_installation: nil)
      adapter = described_class.new(
        bot_token: "xoxb-static-fallback",
        client_id: "client",
        installation_provider: provider,
        signing_secret: signing_secret
      )
      allow(adapter.client).to receive(:auth_test).and_return({})

      expect(adapter.parse_events(request_for(installation_payload)).size).to eq(1)
      expect(adapter.client.token).to eq("xoxb-static-fallback")
    end

    it "uses the provider bot_user_id for mention classification" do
      provider = double("installation provider")
      allow(provider).to receive(:get_installation)
        .and_return({"bot_token" => "xoxb-provider", "bot_user_id" => "B_PROVIDER"})
      adapter = described_class.new(installation_provider: provider, signing_secret: signing_secret)

      event = adapter.parse_events(
        request_for(installation_payload(text: "hello <@B_PROVIDER>", event_type: "message"))
      ).first

      expect(event.message.is_mention).to be(true)
    end

    it "does not reuse a previous workspace client after a failed resolution" do
      provider = double("installation provider")
      provider_calls = 0
      allow(provider).to receive(:get_installation) do |installation_id, **_options|
        provider_calls += 1
        if installation_id == "T_FIRST" && provider_calls == 1
          {"bot_token" => "xoxb-first"}
        elsif installation_id == "T_SECOND"
          {"bot_token" => "xoxb-second"}
        elsif installation_id == "T_FIRST" && provider_calls == 4
          {"bot_token" => "xoxb-rotated"}
        end
      end
      adapter = described_class.new(installation_provider: provider, signing_secret: signing_secret)

      adapter.parse_events(request_for(installation_payload(team_id: "T_FIRST")))
      first_client = adapter.client
      expect(first_client.token).to eq("xoxb-first")

      adapter.parse_events(request_for(installation_payload(team_id: "T_SECOND")))
      second_client = adapter.client
      expect(second_client.token).to eq("xoxb-second")
      expect(second_client).not_to equal(first_client)

      expect(adapter.parse_events(request_for(installation_payload(team_id: "T_FIRST")))).to eq([])
      expect(adapter.client).to be_nil

      adapter.parse_events(request_for(installation_payload(team_id: "T_FIRST")))
      expect(adapter.client.token).to eq("xoxb-rotated")
      expect(adapter.client).not_to equal(first_client)
    end

    it "isolates request context between adapter instances" do
      provider_a = double("provider A", get_installation: {"bot_token" => "xoxb-adapter-a"})
      provider_b = double("provider B", get_installation: nil)
      adapter_a = described_class.new(installation_provider: provider_a, signing_secret: signing_secret)
      adapter_b = described_class.new(installation_provider: provider_b, signing_secret: signing_secret)

      adapter_a.parse_events(request_for(installation_payload))
      adapter_b.parse_events(request_for(installation_payload))

      expect(adapter_a.client.token).to eq("xoxb-adapter-a")
      expect(adapter_b.client).to be_nil
    end

    it "rejects an invalid installation provider" do
      expect {
        described_class.new(installation_provider: "not-a-provider", signing_secret: signing_secret)
      }.to raise_error(ChatSDK::ConfigurationError, /installation_provider must respond/)
    end
  end

  describe "#with_bot_token" do
    it "restores the previous context after the block" do
      adapter = described_class.new(client_id: "client", signing_secret: signing_secret)

      result = adapter.with_bot_token("xoxb-temporary", installation_id: "T_TEMP") do
        expect(adapter.client.token).to eq("xoxb-temporary")
        :block_result
      end

      expect(result).to eq(:block_result)
      expect(adapter.client).to be_nil
    end

    it "supports nested contexts and restores the outer token" do
      adapter = described_class.new(client_id: "client", signing_secret: signing_secret)

      adapter.with_bot_token("xoxb-outer", installation_id: "T_OUTER") do
        expect(adapter.client.token).to eq("xoxb-outer")
        adapter.with_bot_token("xoxb-inner", installation_id: "T_INNER") do
          expect(adapter.client.token).to eq("xoxb-inner")
        end
        expect(adapter.client.token).to eq("xoxb-outer")
      end
    end

    it "restores context when the block raises" do
      adapter = described_class.new(client_id: "client", signing_secret: signing_secret)

      expect {
        adapter.with_bot_token("xoxb-temporary") { raise "block error" }
      }.to raise_error("block error")
      expect(adapter.client).to be_nil
    end

    it "uses the contextual installation ID for concurrency scope" do
      adapter = described_class.new(client_id: "client", signing_secret: signing_secret)
      event = ChatSDK::Events::Mention.new(
        message: ChatSDK::Message.new(
          id: "M1",
          text: "",
          author: ChatSDK::Author.new(id: "U1", name: "user", platform: :slack),
          thread_id: "T1",
          channel_id: "C1",
          platform: :slack
        ),
        thread_id: "T1",
        channel_id: "C1",
        platform: :slack,
        adapter_name: :slack,
        raw: {"team_id" => "T_RAW"}
      )

      adapter.with_bot_token("xoxb-context", installation_id: "E_CONTEXT") do
        expect(adapter.concurrency_scope(event)).to eq("E_CONTEXT")
      end
      expect(adapter.concurrency_scope(event)).to eq("T_RAW")
    end
  end

  describe "installation token encryption" do
    let(:state) { ChatSDK::State::Memory.new }
    let(:key) { "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" }

    it "encrypts stored tokens and decrypts installations while preserving metadata" do
      adapter = described_class.new(
        client_id: "client",
        client_secret: "secret",
        signing_secret: signing_secret,
        encryption_key: key
      )
      adapter.set_state(state)
      adapter.set_installation("T_ENCRYPTED",
        bot_token: "xoxb-secret-token",
        bot_user_id: "B_ENCRYPTED",
        team_name: "Encrypted Team")

      stored = state.get("slack:installation:T_ENCRYPTED")
      expect(stored["bot_token"]).to include("iv", "data", "tag")
      expect(JSON.generate(stored["bot_token"])).not_to include("xoxb-secret-token")
      expect(adapter.get_installation("T_ENCRYPTED")).to include(
        "bot_token" => "xoxb-secret-token",
        "bot_user_id" => "B_ENCRYPTED",
        "team_name" => "Encrypted Team"
      )
    end

    it "keeps reading plaintext installation tokens when encryption is enabled" do
      adapter = described_class.new(
        client_id: "client",
        signing_secret: signing_secret,
        encryption_key: key
      )
      adapter.set_state(state)
      state.set("slack:installation:T_PLAIN", {
        "bot_token" => "xoxb-legacy-token",
        "bot_user_id" => "B_LEGACY",
        "team_name" => "Legacy Team"
      })

      expect(adapter.get_installation("T_PLAIN")["bot_token"]).to eq("xoxb-legacy-token")
    end

    it "raises when encrypted installation data is read without a key" do
      encrypted_token = ChatSDK::Slack::TokenEncryption.encrypt(
        "xoxb-secret-token",
        ChatSDK::Slack::TokenEncryption.decode_key(key)
      )
      adapter = described_class.new(client_id: "client", signing_secret: signing_secret)
      adapter.set_state(state)
      state.set("slack:installation:T_ENCRYPTED", {"bot_token" => encrypted_token})

      expect { adapter.get_installation("T_ENCRYPTED") }
        .to raise_error(ChatSDK::ConfigurationError, /encrypted; configure encryption_key/)
    end

    it "rejects invalid encryption keys during initialization" do
      expect {
        described_class.new(bot_token: bot_token, signing_secret: signing_secret, encryption_key: "short")
      }.to raise_error(ChatSDK::ConfigurationError, /must decode to exactly 32 bytes/)
    end

    it "reads the encryption key from SLACK_ENCRYPTION_KEY" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SLACK_ENCRYPTION_KEY").and_return(key)
      adapter = described_class.new(client_id: "client", signing_secret: signing_secret)
      adapter.set_state(state)
      adapter.set_installation("T_ENV", bot_token: "xoxb-env-token")

      expect(state.get("slack:installation:T_ENV")["bot_token"]).to be_a(Hash)
      expect(adapter.get_installation("T_ENV")["bot_token"]).to eq("xoxb-env-token")
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

    it "raises ArgumentError without a block" do
      expect { subject.start_socket_mode(app_token: "xapp-test-token") }
        .to raise_error(ArgumentError, /requires a block/)
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

    it "classifies message events received through Socket Mode" do
      adapter = described_class.new(bot_token: bot_token, signing_secret: signing_secret, bot_user_id: "B456")
      socket_double = instance_double(ChatSDK::Slack::SocketMode)
      allow(ChatSDK::Slack::SocketMode).to receive(:new).and_return(socket_double)
      socket_callback = nil
      allow(socket_double).to receive(:start) { |&callback| socket_callback = callback }
      yielded_events = []

      adapter.start_socket_mode(app_token: "xapp-test-token") { |event| yielded_events << event }

      event = ChatSDK::Slack::EventParser.parse(
        {
          "type" => "event_callback",
          "event" => {
            "type" => "message",
            "user" => "U123",
            "text" => "<@B456>",
            "ts" => "1234567890.123456",
            "channel" => "C789",
            "channel_type" => "channel"
          }
        }
      ).first
      socket_callback.call(event)

      expect(event.message.is_mention).to be(true)
      expect(yielded_events).to eq([event])
    end

    it "selects each workspace client before Socket Mode handlers run" do
      adapter = described_class.new(
        client_id: "client-id",
        client_secret: "client-secret",
        signing_secret: signing_secret
      )
      adapter.set_state(ChatSDK::State::Memory.new)
      adapter.set_installation("TEAM_A", bot_token: "xoxb-team-a")
      adapter.set_installation("TEAM_B", bot_token: "xoxb-team-b")

      client_a = instance_double(::Slack::Web::Client)
      client_b = instance_double(::Slack::Web::Client)
      allow(adapter).to receive(:build_client).with(token: "xoxb-team-a").and_return(client_a)
      allow(adapter).to receive(:build_client).with(token: "xoxb-team-b").and_return(client_b)
      allow(client_a).to receive(:chat_postMessage).and_return({"ts" => "reply-a"})
      allow(client_b).to receive(:chat_postMessage).and_return({"ts" => "reply-b"})

      socket_double = instance_double(ChatSDK::Slack::SocketMode)
      allow(ChatSDK::Slack::SocketMode).to receive(:new).and_return(socket_double)
      socket_callback = nil
      allow(socket_double).to receive(:start) { |&callback| socket_callback = callback }

      adapter.start_socket_mode(app_token: "xapp-test-token") do |event|
        adapter.post_message(channel_id: event.channel_id, message: "reply")
      end

      %w[TEAM_A TEAM_B].each do |team_id|
        payload = {
          "type" => "event_callback",
          "team_id" => team_id,
          "event" => {
            "type" => "app_mention",
            "user" => "U123",
            "text" => "<@B456> hello",
            "ts" => "1234567890.123456",
            "channel" => "C789",
            "channel_type" => "channel"
          }
        }
        socket_callback.call(ChatSDK::Slack::EventParser.parse(payload).first, payload)
      end

      expect(client_a).to have_received(:chat_postMessage).with(channel: "C789", text: "reply").once
      expect(client_b).to have_received(:chat_postMessage).with(channel: "C789", text: "reply").once
    end

    it "uses the event workspace client for Socket Mode mention classification" do
      adapter = described_class.new(
        client_id: "client-id",
        client_secret: "client-secret",
        signing_secret: signing_secret
      )
      adapter.set_state(ChatSDK::State::Memory.new)
      adapter.set_installation("TEAM_A", bot_token: "xoxb-team-a")
      adapter.set_installation("TEAM_B", bot_token: "xoxb-team-b")

      client_a = instance_double(::Slack::Web::Client)
      client_b = instance_double(::Slack::Web::Client)
      allow(adapter).to receive(:build_client).with(token: "xoxb-team-a").and_return(client_a)
      allow(adapter).to receive(:build_client).with(token: "xoxb-team-b").and_return(client_b)
      allow(client_a).to receive(:auth_test).and_return({"user_id" => "B_TEAM_A"})
      allow(client_b).to receive(:auth_test).and_return({"user_id" => "B_TEAM_B"})

      socket_double = instance_double(ChatSDK::Slack::SocketMode)
      allow(ChatSDK::Slack::SocketMode).to receive(:new).and_return(socket_double)
      socket_callback = nil
      allow(socket_double).to receive(:start) { |&callback| socket_callback = callback }

      adapter.start_socket_mode(app_token: "xapp-test-token") { |_| }

      payload = {
        "type" => "event_callback",
        "team_id" => "TEAM_B",
        "event" => {
          "type" => "message",
          "user" => "U123",
          "text" => "<@B_TEAM_B>",
          "ts" => "1234567890.123456",
          "channel" => "C789",
          "channel_type" => "channel"
        }
      }
      event = ChatSDK::Slack::EventParser.parse(payload).first
      socket_callback.call(event, payload)

      expect(event.message.is_mention).to be(true)
      expect(client_a).not_to have_received(:auth_test)
      expect(client_b).to have_received(:auth_test).once
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
