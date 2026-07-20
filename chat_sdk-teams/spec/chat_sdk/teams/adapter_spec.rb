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

    it "raises PlatformError when no service URL is registered" do
      expect { subject.start_typing(channel_id: "unknown-conv") }
        .to raise_error(ChatSDK::PlatformError, /No service URL/)
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

    it "raises NotSupportedError for fetch_messages" do
      expect { subject.fetch_messages(channel_id: "C1") }
        .to raise_error(ChatSDK::NotSupportedError)
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

    it "does not support message_history capability" do
      expect(subject.supports?(:message_history)).to be false
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
        expect(result["version"]).to eq("1.4")
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
        expect(approve["data"]).to eq({"action" => "btn:approve", "value" => "yes"})
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

        action_set = result["body"][0]
        choice_set = action_set["actions"][0]
        expect(choice_set["type"]).to eq("Input.ChoiceSet")
        expect(choice_set["id"]).to eq("severity_select")
        expect(choice_set["placeholder"]).to eq("Choose severity")
        expect(choice_set["choices"].size).to eq(2)
        expect(choice_set["choices"][0]).to eq({"title" => "SEV1", "value" => "sev1"})
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

    it "raises PlatformError when no service URL is registered" do
      expect { subject.post_message(channel_id: "unknown-conv", message: "Hello") }
        .to raise_error(ChatSDK::PlatformError, /No service URL/)
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
end
