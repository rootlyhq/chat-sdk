# frozen_string_literal: true

require_relative "../../spec_helper"
require "openssl"
require "rack"

RSpec.describe ChatSDK::Teams::Adapter do
  subject { described_class.new(app_id: app_id, app_password: app_password, tenant_id: tenant_id) }

  let(:app_id) { "test-app-id-12345" }
  let(:app_password) { "test-app-password-secret" }
  let(:tenant_id) { "test-tenant-id" }

  it_behaves_like "a chat_sdk platform adapter"

  describe "#initialize" do
    it "raises ConfigurationError without app_id" do
      expect { described_class.new(app_id: nil, app_password: app_password) }
        .to raise_error(ChatSDK::ConfigurationError, /app_id required/)
    end

    it "raises ConfigurationError without app_password" do
      expect { described_class.new(app_id: app_id, app_password: nil) }
        .to raise_error(ChatSDK::ConfigurationError, /app_password required/)
    end
  end

  describe "#name" do
    it "returns :teams" do
      expect(subject.name).to eq(:teams)
    end
  end

  describe "#client" do
    it "returns a BotFrameworkClient" do
      expect(subject.client).to be_a(ChatSDK::Teams::BotFrameworkClient)
    end
  end

  describe "#mention" do
    it "formats a Teams mention" do
      expect(subject.mention("user-123")).to eq("<at>user-123</at>")
    end
  end

  describe "#verify_request!" do
    let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
    let(:kid) { "test-key-id" }

    def build_jwt(payload = {}, key: rsa_key, kid_header: kid, algorithm: "RS256")
      default_payload = {
        "aud" => app_id,
        "iss" => "https://api.botframework.com",
        "exp" => Time.now.to_i + 3600,
        "iat" => Time.now.to_i
      }
      JWT.encode(default_payload.merge(payload), key, algorithm, {kid: kid_header})
    end

    def build_jwks_response(public_key, kid_value)
      key_params = public_key.params
      {
        "keys" => [{
          "kty" => "RSA",
          "kid" => kid_value,
          "n" => Base64.urlsafe_encode64(key_params["n"].to_s(2), padding: false),
          "e" => Base64.urlsafe_encode64(key_params["e"].to_s(2), padding: false)
        }]
      }
    end

    def parse_trusted_activity(adapter, activity)
      token = build_jwt({"serviceurl" => activity.fetch("serviceUrl")})
      env = Rack::MockRequest.env_for(
        "/api/messages",
        :method => "POST",
        :input => JSON.generate(activity),
        "CONTENT_TYPE" => "application/json",
        "HTTP_AUTHORIZATION" => "Bearer #{token}"
      )
      request = Rack::Request.new(env)
      adapter.verify_request!(request)
      adapter.parse_events(request)
    end

    before do
      openid_config = {"jwks_uri" => "https://login.botframework.com/v1/.well-known/keys"}
      stub_request(:get, ChatSDK::Teams::JwtVerifier::OPENID_CONFIG_URL)
        .to_return(status: 200, body: JSON.generate(openid_config), headers: {"Content-Type" => "application/json"})

      jwks = build_jwks_response(rsa_key.public_key, kid)
      stub_request(:get, "https://login.botframework.com/v1/.well-known/keys")
        .to_return(status: 200, body: JSON.generate(jwks), headers: {"Content-Type" => "application/json"})
    end

    it "accepts a valid JWT" do
      token = build_jwt
      env = Rack::MockRequest.env_for(
        "/api/messages",
        :method => "POST",
        :input => '{"type":"message"}',
        "CONTENT_TYPE" => "application/json",
        "HTTP_AUTHORIZATION" => "Bearer #{token}"
      )
      request = Rack::Request.new(env)
      expect(subject.verify_request!(request)).to be(true)
    end

    it "trusts only HTTPS service URLs matching the verified serviceurl claim" do
      state = ChatSDK::State::Memory.new
      subject.set_state(state)
      allow(subject.client).to receive(:send_activity).and_return({"id" => "reply-1"})
      existing_url = "https://existing.example/teams/"
      subject.register_service_url("mismatch-conversation", existing_url)
      cases = [
        {
          conversation_id: "matching-conversation",
          service_url: "https://smba.trafficmanager.net/teams/",
          claim: "https://smba.trafficmanager.net/teams/",
          expected_url: "https://smba.trafficmanager.net/teams/"
        },
        {
          conversation_id: "normalized-trailing-slash-conversation",
          service_url: "https://smba.trafficmanager.net/amer",
          claim: "https://smba.trafficmanager.net/amer/",
          expected_url: "https://smba.trafficmanager.net/amer"
        },
        {
          conversation_id: "normalized-case-conversation",
          service_url: "https://smba.trafficmanager.net/amer",
          claim: "HTTPS://SMBA.TRAFFICMANAGER.NET/amer",
          expected_url: "https://smba.trafficmanager.net/amer"
        },
        {
          conversation_id: "mismatch-conversation",
          service_url: "https://attacker.example/teams/",
          claim: "https://smba.trafficmanager.net/teams/",
          expected_url: existing_url
        },
        {
          conversation_id: "insecure-conversation",
          service_url: "http://smba.trafficmanager.net/teams/",
          claim: "http://smba.trafficmanager.net/teams/",
          expected_url: ChatSDK::Teams::Adapter::DEFAULT_SERVICE_URL
        }
      ]

      cases.each do |test_case|
        token = build_jwt({"serviceurl" => test_case.fetch(:claim)})
        activity = {
          "type" => "message",
          "text" => "hello",
          "from" => {"id" => "user-1"},
          "conversation" => {"id" => test_case.fetch(:conversation_id)},
          "serviceUrl" => test_case.fetch(:service_url)
        }
        env = Rack::MockRequest.env_for(
          "/api/messages",
          :method => "POST",
          :input => JSON.generate(activity),
          "CONTENT_TYPE" => "application/json",
          "HTTP_AUTHORIZATION" => "Bearer #{token}"
        )
        request = Rack::Request.new(env)

        subject.verify_request!(request)
        expect(request.env[ChatSDK::Teams::Adapter::VERIFIED_JWT_CLAIMS_ENV_KEY])
          .to include("serviceurl" => test_case.fetch(:claim))
        subject.parse_events(request)

        conversation_id = test_case.fetch(:conversation_id)
        subject.post_message(channel_id: conversation_id, message: "reply")
        expect(subject.client).to have_received(:send_activity).with(
          service_url: test_case.fetch(:expected_url),
          conversation_id: conversation_id,
          activity: anything
        )
      end

      expect(state.get("chat_sdk:teams:service_url:matching-conversation"))
        .to eq("https://smba.trafficmanager.net/teams/")
      expect(state.get("chat_sdk:teams:service_url:normalized-trailing-slash-conversation"))
        .to eq("https://smba.trafficmanager.net/amer")
      expect(state.get("chat_sdk:teams:service_url:insecure-conversation")).to be_nil
    end

    it "uses shared state for replies and edits in another Chat instance" do
      state = ChatSDK::State::Memory.new
      adapter_a = described_class.new(app_id: app_id, app_password: app_password, tenant_id: tenant_id)
      adapter_b = described_class.new(app_id: app_id, app_password: app_password, tenant_id: tenant_id)
      ChatSDK::Chat.new(user_name: "test-bot", adapters: {teams: adapter_a}, state: state)
      ChatSDK::Chat.new(user_name: "test-bot", adapters: {teams: adapter_b}, state: state)
      service_url = "https://smba.trafficmanager.net/amer/"
      conversation_id = "cross-process-conversation"
      allow(adapter_b.client).to receive(:send_activity).and_return({"id" => "reply-1"})
      allow(adapter_b.client).to receive(:update_activity)

      parse_trusted_activity(adapter_a, {
        "type" => "message",
        "text" => "hello",
        "from" => {"id" => "29:user-1"},
        "conversation" => {"id" => conversation_id},
        "serviceUrl" => service_url
      })

      adapter_b.post_message(channel_id: conversation_id, message: "reply")
      adapter_b.edit_message(channel_id: conversation_id, message_id: "reply-1", message: "edited")

      expect(adapter_b.client).to have_received(:send_activity).with(
        service_url: service_url,
        conversation_id: conversation_id,
        activity: anything
      )
      expect(adapter_b.client).to have_received(:update_activity).with(
        service_url: service_url,
        conversation_id: conversation_id,
        activity_id: "reply-1",
        activity: anything
      )
    end

    it "does not persist untrusted service URLs for conversations or users" do
      state = ChatSDK::State::Memory.new
      adapter_a = described_class.new(app_id: app_id, app_password: app_password, tenant_id: tenant_id)
      adapter_b = described_class.new(app_id: app_id, app_password: app_password, tenant_id: tenant_id)
      ChatSDK::Chat.new(user_name: "test-bot", adapters: {teams: adapter_a}, state: state)
      ChatSDK::Chat.new(user_name: "test-bot", adapters: {teams: adapter_b}, state: state)
      activity = {
        "type" => "message",
        "text" => "hello",
        "from" => {"id" => "29:user-untrusted"},
        "conversation" => {"id" => "untrusted-conversation"},
        "serviceUrl" => "https://attacker.example/teams/"
      }
      token = build_jwt({"serviceurl" => "https://smba.trafficmanager.net/teams/"})
      env = Rack::MockRequest.env_for(
        "/api/messages",
        :method => "POST",
        :input => JSON.generate(activity),
        "CONTENT_TYPE" => "application/json",
        "HTTP_AUTHORIZATION" => "Bearer #{token}"
      )
      request = Rack::Request.new(env)
      adapter_a.verify_request!(request)
      adapter_a.parse_events(request)
      allow(adapter_b.client).to receive(:send_activity).and_return({"id" => "reply-1"})

      expect(state.get("chat_sdk:teams:service_url:untrusted-conversation")).to be_nil
      expect(state.get("chat_sdk:teams:user_service_url:29:user-untrusted")).to be_nil

      adapter_b.post_message(channel_id: "untrusted-conversation", message: "reply")

      expect(adapter_b.client).to have_received(:send_activity).with(
        service_url: ChatSDK::Teams::Adapter::DEFAULT_SERVICE_URL,
        conversation_id: "untrusted-conversation",
        activity: anything
      )
    end

    it "resolves service URLs from event registration, state, and configured defaults in order" do
      state = ChatSDK::State::Memory.new
      configured_url = "https://custom.example/teams/"
      adapter = described_class.new(
        app_id: app_id,
        app_password: app_password,
        tenant_id: tenant_id,
        service_url: configured_url
      )
      ChatSDK::Chat.new(user_name: "test-bot", adapters: {teams: adapter}, state: state)
      allow(adapter.client).to receive(:send_activity).and_return({"id" => "reply-1"})
      parse_trusted_activity(adapter, {
        "type" => "message",
        "text" => "hello",
        "from" => {"id" => "29:user-1"},
        "conversation" => {"id" => "event-conversation"},
        "serviceUrl" => "https://smba.trafficmanager.net/amer/"
      })
      state.set("chat_sdk:teams:service_url:event-conversation", "https://state.example/teams/")
      state.set("chat_sdk:teams:service_url:state-conversation", "https://state.example/teams/")

      adapter.post_message(channel_id: "event-conversation", message: "reply")
      adapter.post_message(channel_id: "state-conversation", message: "reply")
      adapter.post_message(channel_id: "configured-conversation", message: "reply")

      expect(adapter.client).to have_received(:send_activity).with(
        service_url: "https://smba.trafficmanager.net/amer/",
        conversation_id: "event-conversation",
        activity: anything
      )
      expect(adapter.client).to have_received(:send_activity).with(
        service_url: "https://state.example/teams/",
        conversation_id: "state-conversation",
        activity: anything
      )
      expect(adapter.client).to have_received(:send_activity).with(
        service_url: configured_url,
        conversation_id: "configured-conversation",
        activity: anything
      )

      default_adapter = described_class.new(app_id: app_id, app_password: app_password, tenant_id: tenant_id)
      ChatSDK::Chat.new(user_name: "test-bot", adapters: {teams: default_adapter}, state: state)
      allow(default_adapter.client).to receive(:send_activity).and_return({"id" => "reply-2"})
      default_adapter.post_message(channel_id: "unknown-conversation", message: "reply")

      expect(default_adapter.client).to have_received(:send_activity).with(
        service_url: ChatSDK::Teams::Adapter::DEFAULT_SERVICE_URL,
        conversation_id: "unknown-conversation",
        activity: anything
      )
    end

    it "reads updated state URLs instead of caching a previous state value" do
      state = ChatSDK::State::Memory.new
      adapter_a = described_class.new(app_id: app_id, app_password: app_password, tenant_id: tenant_id)
      adapter_b = described_class.new(app_id: app_id, app_password: app_password, tenant_id: tenant_id)
      ChatSDK::Chat.new(user_name: "test-bot", adapters: {teams: adapter_a}, state: state)
      ChatSDK::Chat.new(user_name: "test-bot", adapters: {teams: adapter_b}, state: state)
      conversation_id = "updated-conversation"
      first_url = "https://smba.trafficmanager.net/amer/"
      updated_url = "https://smba.trafficmanager.net/emea/"
      state.set("chat_sdk:teams:service_url:#{conversation_id}", first_url)
      allow(adapter_b.client).to receive(:send_activity).and_return({"id" => "reply-1"})

      adapter_b.post_message(channel_id: conversation_id, message: "first reply")
      parse_trusted_activity(adapter_a, {
        "type" => "message",
        "text" => "hello again",
        "from" => {"id" => "29:user-1"},
        "conversation" => {"id" => conversation_id},
        "serviceUrl" => updated_url
      })
      adapter_b.post_message(channel_id: conversation_id, message: "second reply")

      expect(adapter_b.client).to have_received(:send_activity).with(
        service_url: first_url,
        conversation_id: conversation_id,
        activity: anything
      )
      expect(adapter_b.client).to have_received(:send_activity).with(
        service_url: updated_url,
        conversation_id: conversation_id,
        activity: anything
      )
    end

    it "uses a trusted user's state URL when opening a DM across Chat instances" do
      state = ChatSDK::State::Memory.new
      adapter_a = described_class.new(app_id: app_id, app_password: app_password, tenant_id: tenant_id)
      adapter_b = described_class.new(app_id: app_id, app_password: app_password, tenant_id: tenant_id)
      ChatSDK::Chat.new(user_name: "test-bot", adapters: {teams: adapter_a}, state: state)
      ChatSDK::Chat.new(user_name: "test-bot", adapters: {teams: adapter_b}, state: state)
      service_url = "https://smba.trafficmanager.net/amer/"
      user_id = "29:user-1"
      allow(adapter_b.client).to receive_messages(
        create_conversation: {"id" => "new-dm-conversation"},
        send_activity: {"id" => "reply-1"}
      )
      parse_trusted_activity(adapter_a, {
        "type" => "message",
        "text" => "hello",
        "from" => {"id" => user_id},
        "conversation" => {"id" => "origin-conversation"},
        "serviceUrl" => service_url
      })

      dm_conversation_id = adapter_b.open_dm(user_id)
      adapter_b.post_message(channel_id: dm_conversation_id, message: "DM reply")

      expect(state.get("chat_sdk:teams:user_service_url:#{user_id}")).to eq(service_url)
      expect(ChatSDK::Teams::Adapter::USER_SERVICE_URL_TTL).to eq(30 * 24 * 60 * 60)
      expect(adapter_b.client).to have_received(:create_conversation).with(
        service_url: service_url,
        payload: anything
      )
      expect(adapter_b.client).to have_received(:send_activity).with(
        service_url: service_url,
        conversation_id: dm_conversation_id,
        activity: anything
      )

      fallback_adapter = described_class.new(app_id: app_id, app_password: app_password, tenant_id: tenant_id)
      ChatSDK::Chat.new(user_name: "test-bot", adapters: {teams: fallback_adapter}, state: state)
      allow(fallback_adapter.client).to receive(:create_conversation).and_return({"id" => "default-dm-conversation"})
      unknown_dm_conversation_id = fallback_adapter.open_dm("29:unknown-user")

      expect(unknown_dm_conversation_id).to eq("default-dm-conversation")
      expect(fallback_adapter.client).to have_received(:create_conversation).with(
        service_url: ChatSDK::Teams::Adapter::DEFAULT_SERVICE_URL,
        payload: anything
      )
    end

    it "rejects missing authorization header" do
      env = Rack::MockRequest.env_for(
        "/api/messages",
        :method => "POST",
        :input => '{"type":"message"}',
        "CONTENT_TYPE" => "application/json"
      )
      request = Rack::Request.new(env)
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Missing authorization header/)
    end

    it "rejects a JWT with wrong audience" do
      token = build_jwt({"aud" => "wrong-app-id"})
      env = Rack::MockRequest.env_for(
        "/api/messages",
        :method => "POST",
        :input => '{"type":"message"}',
        "CONTENT_TYPE" => "application/json",
        "HTTP_AUTHORIZATION" => "Bearer #{token}"
      )
      request = Rack::Request.new(env)
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /JWT verification failed/)
    end

    it "rejects an expired JWT" do
      token = build_jwt({"exp" => Time.now.to_i - 3600})
      env = Rack::MockRequest.env_for(
        "/api/messages",
        :method => "POST",
        :input => '{"type":"message"}',
        "CONTENT_TYPE" => "application/json",
        "HTTP_AUTHORIZATION" => "Bearer #{token}"
      )
      request = Rack::Request.new(env)
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /JWT verification failed/)
    end
  end

  describe "#parse_events" do
    def build_request(body)
      env = Rack::MockRequest.env_for(
        "/api/messages",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json"
      )
      Rack::Request.new(env)
    end

    context "message activity" do
      it "parses a channel message into SubscribedMessage" do
        activity = {
          "type" => "message",
          "id" => "act-123",
          "text" => "Hello Teams",
          "from" => {"id" => "user-1", "name" => "Alice"},
          "conversation" => {"id" => "conv-1", "conversationType" => "channel"},
          "serviceUrl" => "https://smba.trafficmanager.net/teams/"
        }
        request = build_request(JSON.generate(activity))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::SubscribedMessage)
        expect(event.message.text).to eq("Hello Teams")
        expect(event.message.author.id).to eq("user-1")
        expect(event.message.author.name).to eq("Alice")
        expect(event.channel_id).to eq("conv-1")
        expect(event.platform).to eq(:teams)
        expect(event.adapter_name).to eq(:teams)
      end

      it "parses a personal message into DirectMessage" do
        activity = {
          "type" => "message",
          "id" => "act-456",
          "text" => "Hello bot",
          "from" => {"id" => "user-2", "name" => "Bob"},
          "conversation" => {"id" => "conv-dm-1", "conversationType" => "personal"},
          "serviceUrl" => "https://smba.trafficmanager.net/teams/"
        }
        request = build_request(JSON.generate(activity))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        expect(events.first).to be_a(ChatSDK::Events::DirectMessage)
        expect(events.first.message.text).to eq("Hello bot")
      end

      it "parses a mention into Mention event" do
        activity = {
          "type" => "message",
          "id" => "act-789",
          "text" => "<at>Bot</at> help me",
          "from" => {"id" => "user-3", "name" => "Carol"},
          "conversation" => {"id" => "conv-2", "conversationType" => "channel"},
          "serviceUrl" => "https://smba.trafficmanager.net/teams/",
          "entities" => [{
            "type" => "mention",
            "mentioned" => {"id" => app_id, "name" => "Bot"}
          }]
        }
        request = build_request(JSON.generate(activity))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        expect(events.first).to be_a(ChatSDK::Events::Mention)
        expect(events.first.message.text).to eq("<at>Bot</at> help me")
      end

      it "ignores messages from the bot itself" do
        activity = {
          "type" => "message",
          "id" => "act-self",
          "text" => "My own message",
          "from" => {"id" => app_id, "name" => "Bot"},
          "conversation" => {"id" => "conv-1"},
          "serviceUrl" => "https://smba.trafficmanager.net/teams/"
        }
        request = build_request(JSON.generate(activity))
        events = subject.parse_events(request)
        expect(events).to be_empty
      end
    end

    context "messageReaction activity" do
      it "parses reactionsAdded into Reaction event" do
        activity = {
          "type" => "messageReaction",
          "from" => {"id" => "user-1", "name" => "Alice"},
          "conversation" => {"id" => "conv-1"},
          "replyToId" => "msg-100",
          "reactionsAdded" => [{"type" => "like"}],
          "serviceUrl" => "https://smba.trafficmanager.net/teams/"
        }
        request = build_request(JSON.generate(activity))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Reaction)
        expect(event.emoji).to eq("like")
        expect(event.user_id).to eq("user-1")
        expect(event.message_id).to eq("msg-100")
        expect(event.added?).to be true
      end

      it "parses reactionsRemoved into Reaction event with added=false" do
        activity = {
          "type" => "messageReaction",
          "from" => {"id" => "user-1", "name" => "Alice"},
          "conversation" => {"id" => "conv-1"},
          "replyToId" => "msg-100",
          "reactionsRemoved" => [{"type" => "like"}],
          "serviceUrl" => "https://smba.trafficmanager.net/teams/"
        }
        request = build_request(JSON.generate(activity))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        expect(events.first.added?).to be false
        expect(events.first.removed?).to be true
      end
    end

    context "invoke activity" do
      it "parses invoke with card action data into Action event" do
        activity = {
          "type" => "invoke",
          "name" => "adaptiveCard/action",
          "from" => {"id" => "user-1", "name" => "Alice"},
          "conversation" => {"id" => "conv-1"},
          "value" => {
            "action" => "btn:approve",
            "data" => "yes"
          },
          "serviceUrl" => "https://smba.trafficmanager.net/teams/"
        }
        request = build_request(JSON.generate(activity))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Action)
        expect(event.action_id).to eq("btn:approve")
        expect(event.value).to eq("yes")
        expect(event.user.id).to eq("user-1")
      end
    end

    context "invalid JSON" do
      it "returns empty array for malformed JSON" do
        request = build_request("not json at all")
        events = subject.parse_events(request)
        expect(events).to be_empty
      end
    end

    it "caches the service URL from inbound activities" do
      activity = {
        "type" => "message",
        "id" => "act-1",
        "text" => "hello",
        "from" => {"id" => "user-1"},
        "conversation" => {"id" => "conv-1"},
        "serviceUrl" => "https://smba.trafficmanager.net/teams/"
      }
      request = build_request(JSON.generate(activity))
      subject.parse_events(request)

      # Now we should be able to use the cached service URL
      # We verify by stubbing the token and API call
      stub_request(:post, ChatSDK::Teams::BotFrameworkClient::TOKEN_URL)
        .to_return(
          status: 200,
          body: JSON.generate({"access_token" => "test-token", "expires_in" => 3600}),
          headers: {"Content-Type" => "application/json"}
        )
      stub_request(:post, "https://smba.trafficmanager.net/teams/v3/conversations/conv-1/activities")
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "new-msg-1"}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.post_message(channel_id: "conv-1", message: "Test reply")
      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("new-msg-1")
    end
  end

  describe "#upload_file" do
    it "normalizes the parent reply id for a channel thread" do
      service_url = "https://smba.trafficmanager.net/teams/"
      subject.register_service_url("conv-1", service_url)
      allow(subject.client).to receive(:send_activity).and_return({"id" => "upload-1"})

      subject.upload_file(
        channel_id: "conv-1",
        io: double(read: "file contents"),
        filename: "report.txt",
        thread_id: "conv-1;messageid=parent-1"
      )

      expect(subject.client).to have_received(:send_activity).with(
        service_url: service_url,
        conversation_id: "conv-1",
        activity: hash_including("replyToId" => "parent-1")
      )
    end
  end

  describe "#start_typing" do
    before do
      subject.register_service_url("conv-1", "https://smba.trafficmanager.net/teams/")

      stub_request(:post, ChatSDK::Teams::BotFrameworkClient::TOKEN_URL)
        .to_return(
          status: 200,
          body: JSON.generate({"access_token" => "test-token", "expires_in" => 3600}),
          headers: {"Content-Type" => "application/json"}
        )
    end

    it "sends a typing activity" do
      stub_request(:post, "https://smba.trafficmanager.net/teams/v3/conversations/conv-1/activities")
        .with { |req|
          body = JSON.parse(req.body)
          body["type"] == "typing"
        }
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "typing-1"}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.start_typing(channel_id: "conv-1") }.not_to raise_error
    end

    it "supports typing_indicator capability" do
      expect(subject.supports?(:typing_indicator)).to be true
    end

    it "uses the default service URL when no conversation URL is registered" do
      allow(subject.client).to receive(:send_typing)

      subject.start_typing(channel_id: "unknown-conv")

      expect(subject.client).to have_received(:send_typing).with(
        service_url: ChatSDK::Teams::Adapter::DEFAULT_SERVICE_URL,
        conversation_id: "unknown-conv"
      )
    end
  end

  describe "capability gaps" do
    it "raises NotSupportedError for ephemeral messages" do
      expect { subject.post_ephemeral(channel_id: "C1", user_id: "U1", message: ChatSDK::PostableMessage.new(text: "t")) }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "raises NotSupportedError for modals" do
      expect { subject.open_modal(trigger_id: "T1", modal: ChatSDK::Cards::Node.new(:modal)) }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "raises NotSupportedError for add_reaction" do
      expect { subject.add_reaction(channel_id: "C1", message_id: "M1", emoji: "like") }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "raises NotSupportedError for remove_reaction" do
      expect { subject.remove_reaction(channel_id: "C1", message_id: "M1", emoji: "like") }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "raises ConfigurationError for fetch_messages without Graph API credentials" do
      expect { subject.fetch_messages(channel_id: "C1") }
        .to raise_error(ChatSDK::ConfigurationError, /Graph API credentials/)
    end

    it "does not support ephemeral_messages capability" do
      expect(subject.supports?(:ephemeral_messages)).to be false
    end

    it "does not support modals capability" do
      expect(subject.supports?(:modals)).to be false
    end

    it "does not support reactions capability" do
      expect(subject.supports?(:reactions)).to be false
    end

    it "supports message_history capability" do
      expect(subject.supports?(:message_history)).to be true
    end

    it "still parses inbound reactions from activities" do
      activity = {
        "type" => "messageReaction",
        "from" => {"id" => "user-1", "name" => "Alice"},
        "conversation" => {"id" => "conv-1"},
        "replyToId" => "msg-100",
        "reactionsAdded" => [{"type" => "like"}],
        "serviceUrl" => "https://smba.trafficmanager.net/teams/"
      }
      env = Rack::MockRequest.env_for(
        "/api/messages",
        :method => "POST",
        :input => JSON.generate(activity),
        "CONTENT_TYPE" => "application/json"
      )
      request = Rack::Request.new(env)
      events = subject.parse_events(request)

      expect(events.size).to eq(1)
      expect(events.first).to be_a(ChatSDK::Events::Reaction)
      expect(events.first.emoji).to eq("like")
    end
  end

  describe ChatSDK::Teams::AdaptiveCardRenderer do
    let(:renderer) { described_class.new }

    describe "#render" do
      it "renders a text node as AdaptiveCard with TextBlock" do
        node = ChatSDK::Cards::Node.new(:text, attributes: {content: "Hello world"})
        result = renderer.render(node)

        expect(result["type"]).to eq("AdaptiveCard")
        expect(result["version"]).to eq("1.5")
        expect(result["body"].size).to eq(1)
        expect(result["body"][0]["type"]).to eq("TextBlock")
        expect(result["body"][0]["text"]).to eq("Hello world")
        expect(result["body"][0]["wrap"]).to be(true)
      end

      it "renders a card with multiple children" do
        card = ChatSDK.card do
          text "Line 1"
          divider
          text "Line 2"
        end
        result = renderer.render(card)

        expect(result["type"]).to eq("AdaptiveCard")
        expect(result["body"].size).to eq(2)
        expect(result["body"][0]["type"]).to eq("TextBlock")
        expect(result["body"][0]["text"]).to eq("Line 1")
        # Divider is rendered as separator on next element
        expect(result["body"][1]["separator"]).to be(true)
        expect(result["body"][1]["text"]).to eq("Line 2")
      end

      it "renders fields as FactSet" do
        card = ChatSDK.card do
          fields do
            field "Status", "Active"
            field "Severity", "SEV1"
          end
        end
        result = renderer.render(card)

        fact_set = result["body"][0]
        expect(fact_set["type"]).to eq("FactSet")
        expect(fact_set["facts"].size).to eq(2)
        expect(fact_set["facts"][0]).to eq({"title" => "Status", "value" => "Active"})
        expect(fact_set["facts"][1]).to eq({"title" => "Severity", "value" => "SEV1"})
      end

      it "renders an image" do
        card = ChatSDK.card do
          image url: "https://example.com/img.png", alt: "Screenshot"
        end
        result = renderer.render(card)

        expect(result["body"][0]["type"]).to eq("Image")
        expect(result["body"][0]["url"]).to eq("https://example.com/img.png")
        expect(result["body"][0]["altText"]).to eq("Screenshot")
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

        action_set = result["body"][0]
        expect(action_set["type"]).to eq("ActionSet")
        expect(action_set["actions"].size).to eq(3)

        approve = action_set["actions"][0]
        expect(approve["type"]).to eq("Action.Submit")
        expect(approve["title"]).to eq("Approve")
        expect(approve["data"]).to eq({"actionId" => "btn:approve", "value" => "yes"})
        expect(approve["style"]).to eq("positive")

        reject = action_set["actions"][1]
        expect(reject["type"]).to eq("Action.Submit")
        expect(reject["title"]).to eq("Reject")
        expect(reject["style"]).to eq("destructive")

        link = action_set["actions"][2]
        expect(link["type"]).to eq("Action.OpenUrl")
        expect(link["title"]).to eq("View")
        expect(link["url"]).to eq("https://example.com")
      end

      it "renders a select menu as Input.ChoiceSet" do
        card = ChatSDK.card do
          actions do
            select id: "severity_select", placeholder: "Choose severity" do
              option "SEV1", value: "sev1"
              option "SEV2", value: "sev2"
            end
          end
        end
        result = renderer.render(card)

        choice_set = result["body"][0]
        expect(choice_set["type"]).to eq("Input.ChoiceSet")
        expect(choice_set["id"]).to eq("severity_select")
        expect(choice_set["placeholder"]).to eq("Choose severity")
        expect(choice_set["choices"].size).to eq(2)
        expect(choice_set["choices"][0]).to eq({"title" => "SEV1", "value" => "sev1"})
        expect(result["body"][1]).to eq(
          "type" => "ActionSet",
          "actions" => [
            {
              "type" => "Action.Submit",
              "title" => "Submit",
              "data" => {"actionId" => "__auto_submit"}
            }
          ]
        )
      end

      it "renders a radio select in the body with an automatic submit action" do
        card = ChatSDK.card do
          actions do
            radio_select id: "mode", label: "Mode" do
              option "Fast", value: "fast"
              option "Careful", value: "careful"
            end
          end
        end
        body = renderer.render(card)["body"]

        expect(body[0]).to include(
          "type" => "Input.ChoiceSet",
          "id" => "mode",
          "style" => "expanded"
        )
        expect(body[1]["actions"].first).to include(
          "type" => "Action.Submit",
          "data" => {"actionId" => "__auto_submit"}
        )
      end

      it "renders card styles, links, input options, and radio selections" do
        card = ChatSDK.card(image_url: "https://example.com/header.png") do
          text "Strong", style: :bold
          text "Subtle", style: :muted
          link url: "https://example.com/docs", label: "Docs"
          text_input id: "name", label: "Name", max_length: 80
          actions do
            link_button "Open", url: "https://example.com", style: :primary
            button "Disabled", id: "disabled", disabled: true
            select id: "scope", label: "Scope", initial_option: "team", optional: true do
              option "Team", value: "team"
              option "Personal", value: "personal"
            end
            radio_select id: "mode", label: "Mode", initial_option: "fast" do
              option "Fast", value: "fast"
              option "Careful", value: "careful"
            end
          end
        end
        body = renderer.render(card)["body"]

        expect(body[0]).to eq("type" => "Image", "url" => "https://example.com/header.png", "size" => "Stretch")
        expect(body[1]).to include("weight" => "Bolder")
        expect(body[2]).to include("isSubtle" => true)
        expect(body[3]["text"]).to eq("[Docs](https://example.com/docs)")
        expect(body[4]["maxLength"]).to eq(80)
        select_input = body.find { |element| element["id"] == "scope" }
        radio_input = body.find { |element| element["id"] == "mode" }
        action_set = body.find { |element| element["type"] == "ActionSet" }
        expect(select_input).to include("type" => "Input.ChoiceSet", "style" => "compact")
        expect(radio_input).to include("type" => "Input.ChoiceSet", "style" => "expanded")
        expect(body.index(select_input)).to be < body.index(action_set)
        expect(body.index(radio_input)).to be < body.index(action_set)
        actions = action_set["actions"]
        expect(actions[0]["style"]).to eq("positive")
        expect(actions[1]).not_to have_key("disabled")
        expect(actions.map { |action| action["type"] }).to eq(["Action.OpenUrl", "Action.Submit"])
        expect(actions.map { |action| action.dig("data", "actionId") }).not_to include("__auto_submit")
      end

      it "omits an empty ActionSet" do
        card = ChatSDK.card do
          actions {}
        end

        expect(renderer.render(card)["body"]).to be_empty
      end

      it "renders a section as Container" do
        card = ChatSDK.card do
          section "Details" do
            text "Some info"
          end
        end
        result = renderer.render(card)

        container = result["body"][0]
        expect(container["type"]).to eq("Container")
        expect(container["items"].size).to eq(2)
        expect(container["items"][0]["type"]).to eq("TextBlock")
        expect(container["items"][0]["text"]).to eq("Details")
        expect(container["items"][0]["weight"]).to eq("bolder")
        expect(container["items"][1]["type"]).to eq("TextBlock")
        expect(container["items"][1]["text"]).to eq("Some info")
      end
    end
  end

  describe "#post_message" do
    before do
      # Register a service URL
      subject.register_service_url("conv-1", "https://smba.trafficmanager.net/teams/")

      stub_request(:post, ChatSDK::Teams::BotFrameworkClient::TOKEN_URL)
        .to_return(
          status: 200,
          body: JSON.generate({"access_token" => "test-token", "expires_in" => 3600}),
          headers: {"Content-Type" => "application/json"}
        )
    end

    it "sends a text message" do
      stub_request(:post, "https://smba.trafficmanager.net/teams/v3/conversations/conv-1/activities")
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "msg-1"}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.post_message(channel_id: "conv-1", message: "Hello Teams!")
      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("msg-1")
      expect(result.platform).to eq(:teams)
    end

    it "sends a card message" do
      stub_request(:post, "https://smba.trafficmanager.net/teams/v3/conversations/conv-1/activities")
        .with { |req|
          body = JSON.parse(req.body)
          body["attachments"]&.first&.dig("contentType") == "application/vnd.microsoft.card.adaptive"
        }
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "msg-card-1"}),
          headers: {"Content-Type" => "application/json"}
        )

      card = ChatSDK.card do
        text "Incident Update"
        fields do
          field "Status", "Active"
        end
      end

      result = subject.post_message(channel_id: "conv-1", message: ChatSDK::PostableMessage.new(card: card, text: "Incident Update"))
      expect(result.id).to eq("msg-card-1")
    end

    it "uses the default service URL when no conversation URL is registered" do
      allow(subject.client).to receive(:send_activity).and_return({"id" => "message-1"})

      subject.post_message(channel_id: "unknown-conv", message: "Hello")

      expect(subject.client).to have_received(:send_activity).with(
        service_url: ChatSDK::Teams::Adapter::DEFAULT_SERVICE_URL,
        conversation_id: "unknown-conv",
        activity: hash_including("text" => "Hello")
      )
    end
  end

  describe "#edit_message" do
    before do
      subject.register_service_url("conv-1", "https://smba.trafficmanager.net/teams/")

      stub_request(:post, ChatSDK::Teams::BotFrameworkClient::TOKEN_URL)
        .to_return(
          status: 200,
          body: JSON.generate({"access_token" => "test-token", "expires_in" => 3600}),
          headers: {"Content-Type" => "application/json"}
        )
    end

    it "updates an activity" do
      stub_request(:put, "https://smba.trafficmanager.net/teams/v3/conversations/conv-1/activities/msg-1")
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "msg-1"}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.edit_message(channel_id: "conv-1", message_id: "msg-1", message: "Updated text")
      expect(result["id"]).to eq("msg-1")
    end
  end

  describe "#delete_message" do
    before do
      subject.register_service_url("conv-1", "https://smba.trafficmanager.net/teams/")

      stub_request(:post, ChatSDK::Teams::BotFrameworkClient::TOKEN_URL)
        .to_return(
          status: 200,
          body: JSON.generate({"access_token" => "test-token", "expires_in" => 3600}),
          headers: {"Content-Type" => "application/json"}
        )
    end

    it "deletes an activity" do
      stub_request(:delete, "https://smba.trafficmanager.net/teams/v3/conversations/conv-1/activities/msg-1")
        .to_return(status: 200, body: "", headers: {})

      expect { subject.delete_message(channel_id: "conv-1", message_id: "msg-1") }.not_to raise_error
    end
  end

  describe "#render" do
    it "renders a card as Adaptive Card JSON" do
      card = ChatSDK.card do
        text "Hello"
      end
      msg = ChatSDK::PostableMessage.new(card: card, text: "Hello")

      result = subject.render(msg)
      expect(result["type"]).to eq("AdaptiveCard")
      expect(result["body"][0]["text"]).to eq("Hello")
    end

    it "renders plain text as-is" do
      msg = ChatSDK::PostableMessage.new(text: "Plain text")
      result = subject.render(msg)
      expect(result).to eq("Plain text")
    end
  end

  describe "#fetch_messages" do
    let(:graph_client_id) { "graph-client-id" }
    let(:graph_client_secret) { "graph-client-secret" }
    let(:graph_tenant_id) { "graph-tenant-id" }
    let(:graph_token_url) { "https://login.microsoftonline.com/#{graph_tenant_id}/oauth2/v2.0/token" }

    context "without Graph API credentials" do
      it "raises ConfigurationError" do
        adapter = described_class.new(app_id: app_id, app_password: app_password)
        expect { adapter.fetch_messages(channel_id: "chat-1") }
          .to raise_error(ChatSDK::ConfigurationError, /Graph API credentials/)
      end
    end

    context "with Graph API credentials" do
      subject do
        described_class.new(
          app_id: app_id,
          app_password: app_password,
          graph_client_id: graph_client_id,
          graph_client_secret: graph_client_secret,
          graph_tenant_id: graph_tenant_id
        )
      end

      before do
        stub_request(:post, graph_token_url)
          .to_return(
            status: 200,
            body: JSON.generate({"access_token" => "graph-token", "expires_in" => 3600}),
            headers: {"Content-Type" => "application/json"}
          )
      end

      it "fetches messages from Graph API" do
        graph_response = {
          "value" => [
            {
              "id" => "msg-1",
              "body" => {"contentType" => "text", "content" => "Hello from Graph"},
              "from" => {"user" => {"id" => "user-1", "displayName" => "Alice"}},
              "createdDateTime" => "2024-01-15T10:30:00Z",
              "replyToId" => nil
            },
            {
              "id" => "msg-2",
              "body" => {"contentType" => "text", "content" => "Second message"},
              "from" => {"user" => {"id" => "user-2", "displayName" => "Bob"}},
              "createdDateTime" => "2024-01-15T10:31:00Z",
              "replyToId" => "msg-1"
            }
          ]
        }

        stub_request(:get, "https://graph.microsoft.com/v1.0/chats/chat-1/messages?$top=50&$orderby=createdDateTime%20desc")
          .to_return(
            status: 200,
            body: JSON.generate(graph_response),
            headers: {"Content-Type" => "application/json"}
          )

        messages, next_cursor = subject.fetch_messages(channel_id: "chat-1")

        expect(messages.size).to eq(2)

        expect(messages[0]).to be_a(ChatSDK::Message)
        expect(messages[0].id).to eq("msg-1")
        expect(messages[0].text).to eq("Hello from Graph")
        expect(messages[0].author.id).to eq("user-1")
        expect(messages[0].author.name).to eq("Alice")
        expect(messages[0].author.bot?).to be false
        expect(messages[0].channel_id).to eq("chat-1")
        expect(messages[0].platform).to eq(:teams)
        expect(messages[0].timestamp).to eq("2024-01-15T10:30:00Z")

        expect(messages[1].id).to eq("msg-2")
        expect(messages[1].thread_id).to eq("msg-1")

        expect(next_cursor).to be_nil
      end

      it "returns the next page link when present" do
        graph_response = {
          "value" => [
            {
              "id" => "msg-1",
              "body" => {"contentType" => "text", "content" => "Hello"},
              "from" => {"user" => {"id" => "user-1", "displayName" => "Alice"}},
              "createdDateTime" => "2024-01-15T10:30:00Z"
            }
          ],
          "@odata.nextLink" => "https://graph.microsoft.com/v1.0/chats/chat-1/messages?$skiptoken=abc123"
        }

        stub_request(:get, "https://graph.microsoft.com/v1.0/chats/chat-1/messages?$top=25&$orderby=createdDateTime%20desc")
          .to_return(
            status: 200,
            body: JSON.generate(graph_response),
            headers: {"Content-Type" => "application/json"}
          )

        messages, next_cursor = subject.fetch_messages(channel_id: "chat-1", limit: 25)

        expect(messages.size).to eq(1)
        expect(next_cursor).to eq("https://graph.microsoft.com/v1.0/chats/chat-1/messages?$skiptoken=abc123")
      end

      it "identifies bot messages from application senders" do
        graph_response = {
          "value" => [
            {
              "id" => "msg-bot",
              "body" => {"contentType" => "text", "content" => "Bot reply"},
              "from" => {"application" => {"id" => "app-1", "displayName" => "MyBot"}},
              "createdDateTime" => "2024-01-15T10:30:00Z"
            }
          ]
        }

        stub_request(:get, "https://graph.microsoft.com/v1.0/chats/chat-1/messages?$top=50&$orderby=createdDateTime%20desc")
          .to_return(
            status: 200,
            body: JSON.generate(graph_response),
            headers: {"Content-Type" => "application/json"}
          )

        messages, = subject.fetch_messages(channel_id: "chat-1")

        expect(messages[0].author.id).to eq("app-1")
        expect(messages[0].author.name).to eq("MyBot")
        expect(messages[0].author.bot?).to be true
      end

      it "handles empty results" do
        graph_response = {"value" => []}

        stub_request(:get, "https://graph.microsoft.com/v1.0/chats/chat-1/messages?$top=50&$orderby=createdDateTime%20desc")
          .to_return(
            status: 200,
            body: JSON.generate(graph_response),
            headers: {"Content-Type" => "application/json"}
          )

        messages, next_cursor = subject.fetch_messages(channel_id: "chat-1")

        expect(messages).to be_empty
        expect(next_cursor).to be_nil
      end

      it "raises PlatformError on Graph API failure" do
        stub_request(:get, "https://graph.microsoft.com/v1.0/chats/chat-1/messages?$top=50&$orderby=createdDateTime%20desc")
          .to_return(
            status: 403,
            body: JSON.generate({"error" => {"code" => "Forbidden", "message" => "Insufficient privileges"}}),
            headers: {"Content-Type" => "application/json"}
          )

        expect { subject.fetch_messages(channel_id: "chat-1") }
          .to raise_error(ChatSDK::PlatformError, /Graph API error: 403/)
      end
    end
  end
end
