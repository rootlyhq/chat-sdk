# frozen_string_literal: true

require_relative "../../spec_helper"
require "rack"

RSpec.describe ChatSDK::WhatsApp::Adapter do
  subject do
    described_class.new(
      access_token: access_token,
      app_secret: app_secret,
      phone_number_id: phone_number_id,
      verify_token: verify_token
    )
  end

  let(:access_token) { "EAABsbCS1iZAIBAKx7example" }
  let(:app_secret) { "test_app_secret_123" }
  let(:phone_number_id) { "123456789012345" }
  let(:verify_token) { "my_verify_token" }

  it_behaves_like "a chat_sdk platform adapter"

  describe "#initialize" do
    it "raises ConfigurationError without access_token" do
      expect { described_class.new(access_token: nil, phone_number_id: phone_number_id) }
        .to raise_error(ChatSDK::ConfigurationError, /access_token required/)
    end

    it "raises ConfigurationError without phone_number_id" do
      expect { described_class.new(access_token: access_token, phone_number_id: nil) }
        .to raise_error(ChatSDK::ConfigurationError, /phone_number_id required/)
    end

    it "falls back to environment variables" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("WHATSAPP_ACCESS_TOKEN").and_return("env-token")
      allow(ENV).to receive(:[]).with("WHATSAPP_APP_SECRET").and_return("env-secret")
      allow(ENV).to receive(:[]).with("WHATSAPP_PHONE_NUMBER_ID").and_return("env-phone-id")
      allow(ENV).to receive(:[]).with("WHATSAPP_VERIFY_TOKEN").and_return("env-verify")

      adapter = described_class.new
      expect(adapter.name).to eq(:whatsapp)
    end
  end

  describe "#name" do
    it "returns :whatsapp" do
      expect(subject.name).to eq(:whatsapp)
    end
  end

  describe "#client" do
    it "returns an ApiClient" do
      expect(subject.client).to be_a(ChatSDK::WhatsApp::ApiClient)
    end
  end

  describe "#mention" do
    it "returns the user_id as-is" do
      expect(subject.mention("+15551234567")).to eq("+15551234567")
    end
  end

  describe "#verify_request!" do
    def build_request(body, headers = {})
      env = Rack::MockRequest.env_for(
        "/webhooks/whatsapp",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json",
        **headers
      )
      Rack::Request.new(env)
    end

    it "accepts a valid HMAC-SHA256 signature" do
      body = '{"object":"whatsapp_business_account","entry":[]}'
      signature = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", app_secret, body)}"
      request = build_request(body, "HTTP_X_HUB_SIGNATURE_256" => signature)

      expect(subject.verify_request!(request)).to be(true)
    end

    it "rejects an invalid signature" do
      body = '{"object":"whatsapp_business_account","entry":[]}'
      request = build_request(body, "HTTP_X_HUB_SIGNATURE_256" => "sha256=invalid")

      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Invalid WhatsApp signature/)
    end

    it "rejects missing signature header" do
      body = '{"object":"whatsapp_business_account","entry":[]}'
      request = build_request(body)

      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Missing WhatsApp signature/)
    end
  end

  describe "#ack_response" do
    it "returns challenge for valid GET webhook verification" do
      env = Rack::MockRequest.env_for(
        "/webhooks/whatsapp?hub.mode=subscribe&hub.verify_token=#{verify_token}&hub.challenge=CHALLENGE_STRING",
        method: "GET"
      )
      request = Rack::Request.new(env)

      result = subject.ack_response(request)
      expect(result).to eq([200, {}, ["CHALLENGE_STRING"]])
    end

    it "returns nil for GET with wrong verify_token" do
      env = Rack::MockRequest.env_for(
        "/webhooks/whatsapp?hub.mode=subscribe&hub.verify_token=wrong_token&hub.challenge=CHALLENGE",
        method: "GET"
      )
      request = Rack::Request.new(env)

      expect(subject.ack_response(request)).to be_nil
    end

    it "returns nil for GET with wrong mode" do
      env = Rack::MockRequest.env_for(
        "/webhooks/whatsapp?hub.mode=unsubscribe&hub.verify_token=#{verify_token}&hub.challenge=CHALLENGE",
        method: "GET"
      )
      request = Rack::Request.new(env)

      expect(subject.ack_response(request)).to be_nil
    end

    it "returns nil for POST requests" do
      env = Rack::MockRequest.env_for(
        "/webhooks/whatsapp",
        method: "POST",
        input: '{"object":"whatsapp_business_account"}'
      )
      request = Rack::Request.new(env)

      expect(subject.ack_response(request)).to be_nil
    end
  end

  describe "#parse_events" do
    def build_request(body)
      env = Rack::MockRequest.env_for(
        "/webhooks/whatsapp",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json"
      )
      Rack::Request.new(env)
    end

    context "text message" do
      it "parses into DirectMessage event" do
        payload = {
          "object" => "whatsapp_business_account",
          "entry" => [{
            "id" => "BIZ_ACCOUNT_ID",
            "changes" => [{
              "field" => "messages",
              "value" => {
                "messaging_product" => "whatsapp",
                "metadata" => {"phone_number_id" => phone_number_id},
                "messages" => [{
                  "from" => "15551234567",
                  "id" => "wamid.HBgLMTU1NTEyMzQ1NjcVAgASGBQzRUI",
                  "timestamp" => "1677777777",
                  "type" => "text",
                  "text" => {"body" => "Hello, bot!"}
                }]
              }
            }]
          }]
        }

        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::DirectMessage)
        expect(event.message.text).to eq("Hello, bot!")
        expect(event.message.id).to eq("wamid.HBgLMTU1NTEyMzQ1NjcVAgASGBQzRUI")
        expect(event.message.author.id).to eq("15551234567")
        expect(event.channel_id).to eq("15551234567")
        expect(event.thread_id).to eq("whatsapp:#{phone_number_id}:15551234567")
        expect(event.platform).to eq(:whatsapp)
        expect(event.adapter_name).to eq(:whatsapp)
      end
    end

    context "interactive button reply" do
      it "parses into Action event" do
        payload = {
          "object" => "whatsapp_business_account",
          "entry" => [{
            "id" => "BIZ_ACCOUNT_ID",
            "changes" => [{
              "field" => "messages",
              "value" => {
                "messaging_product" => "whatsapp",
                "metadata" => {"phone_number_id" => phone_number_id},
                "messages" => [{
                  "from" => "15559876543",
                  "id" => "wamid.interactive123",
                  "timestamp" => "1677777777",
                  "type" => "interactive",
                  "interactive" => {
                    "type" => "button_reply",
                    "button_reply" => {
                      "id" => "incident:ack",
                      "title" => "Acknowledge"
                    }
                  }
                }]
              }
            }]
          }]
        }

        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Action)
        expect(event.action_id).to eq("incident:ack")
        expect(event.value).to eq("incident:ack")
        expect(event.user.id).to eq("15559876543")
        expect(event.channel_id).to eq("15559876543")
        expect(event.thread_id).to eq("whatsapp:#{phone_number_id}:15559876543")
        expect(event.platform).to eq(:whatsapp)
      end
    end

    context "interactive list reply" do
      it "parses into Action event" do
        payload = {
          "object" => "whatsapp_business_account",
          "entry" => [{
            "id" => "BIZ_ACCOUNT_ID",
            "changes" => [{
              "field" => "messages",
              "value" => {
                "messaging_product" => "whatsapp",
                "messages" => [{
                  "from" => "15559876543",
                  "id" => "wamid.list123",
                  "timestamp" => "1677777777",
                  "type" => "interactive",
                  "interactive" => {
                    "type" => "list_reply",
                    "list_reply" => {
                      "id" => "severity:sev1",
                      "title" => "SEV1"
                    }
                  }
                }]
              }
            }]
          }]
        }

        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Action)
        expect(event.action_id).to eq("severity:sev1")
      end
    end

    context "status update (delivery report)" do
      it "returns empty array" do
        payload = {
          "object" => "whatsapp_business_account",
          "entry" => [{
            "id" => "BIZ_ACCOUNT_ID",
            "changes" => [{
              "field" => "messages",
              "value" => {
                "messaging_product" => "whatsapp",
                "statuses" => [{
                  "id" => "wamid.status123",
                  "status" => "delivered",
                  "timestamp" => "1677777777",
                  "recipient_id" => "15551234567"
                }]
              }
            }]
          }]
        }

        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events).to be_empty
      end
    end

    context "media message" do
      it "parses image message into DirectMessage" do
        payload = {
          "object" => "whatsapp_business_account",
          "entry" => [{
            "id" => "BIZ_ACCOUNT_ID",
            "changes" => [{
              "field" => "messages",
              "value" => {
                "messaging_product" => "whatsapp",
                "messages" => [{
                  "from" => "15551234567",
                  "id" => "wamid.image123",
                  "timestamp" => "1677777777",
                  "type" => "image",
                  "image" => {
                    "id" => "media_id_123",
                    "mime_type" => "image/jpeg",
                    "caption" => "Check this out"
                  }
                }]
              }
            }]
          }]
        }

        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::DirectMessage)
        expect(event.message.text).to include("Check this out")
        expect(event.message.text).to include("image")
      end
    end

    context "non-whatsapp object" do
      it "returns empty array" do
        payload = {"object" => "instagram", "entry" => []}
        request = build_request(JSON.generate(payload))

        expect(subject.parse_events(request)).to be_empty
      end
    end

    context "invalid JSON" do
      it "returns empty array" do
        request = build_request("not json")
        expect(subject.parse_events(request)).to be_empty
      end
    end

    context "multiple messages" do
      it "parses all events" do
        payload = {
          "object" => "whatsapp_business_account",
          "entry" => [{
            "id" => "BIZ_ACCOUNT_ID",
            "changes" => [{
              "field" => "messages",
              "value" => {
                "messaging_product" => "whatsapp",
                "messages" => [
                  {
                    "from" => "15551111111",
                    "id" => "wamid.1",
                    "timestamp" => "1677777777",
                    "type" => "text",
                    "text" => {"body" => "First"}
                  },
                  {
                    "from" => "15552222222",
                    "id" => "wamid.2",
                    "timestamp" => "1677777778",
                    "type" => "text",
                    "text" => {"body" => "Second"}
                  }
                ]
              }
            }]
          }]
        }

        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(2)
        expect(events[0].message.text).to eq("First")
        expect(events[1].message.text).to eq("Second")
      end
    end
  end

  describe "#post_message" do
    it "sends a text message" do
      stub_request(:post, %r{graph\.facebook\.com/v21\.0/#{phone_number_id}/messages})
        .to_return(
          status: 200,
          body: JSON.generate({
            "messaging_product" => "whatsapp",
            "contacts" => [{"wa_id" => "15551234567"}],
            "messages" => [{"id" => "wamid.resp123"}]
          }),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.post_message(channel_id: "15551234567", message: "Hello!")
      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("wamid.resp123")
      expect(result.platform).to eq(:whatsapp)
    end

    it "sends a card message as interactive" do
      stub_request(:post, %r{graph\.facebook\.com/v21\.0/#{phone_number_id}/messages})
        .with { |req|
          body = JSON.parse(req.body)
          body["type"] == "interactive"
        }
        .to_return(
          status: 200,
          body: JSON.generate({
            "messaging_product" => "whatsapp",
            "messages" => [{"id" => "wamid.card123"}]
          }),
          headers: {"Content-Type" => "application/json"}
        )

      card = ChatSDK.card(title: "Incident #4821") do
        text "Details"
        actions do
          button "Ack", id: "incident:ack", style: :primary, value: "4821"
        end
      end

      result = subject.post_message(
        channel_id: "15551234567",
        message: ChatSDK::PostableMessage.new(card: card, text: "Incident Update")
      )
      expect(result.id).to eq("wamid.card123")
    end
  end

  describe "#add_reaction" do
    it "sends a reaction message" do
      stub = stub_request(:post, %r{graph\.facebook\.com/v21\.0/#{phone_number_id}/messages})
        .with { |req|
          body = JSON.parse(req.body)
          body["type"] == "reaction" && body["reaction"]["emoji"] == "\u{1F44D}"
        }
        .to_return(
          status: 200,
          body: JSON.generate({"messaging_product" => "whatsapp", "messages" => [{"id" => "wamid.react123"}]}),
          headers: {"Content-Type" => "application/json"}
        )

      subject.add_reaction(channel_id: "15551234567", message_id: "wamid.orig123", emoji: "\u{1F44D}")
      expect(stub).to have_been_requested
    end
  end

  describe "#remove_reaction" do
    it "sends a reaction message with empty emoji" do
      stub = stub_request(:post, %r{graph\.facebook\.com/v21\.0/#{phone_number_id}/messages})
        .with { |req|
          body = JSON.parse(req.body)
          body["type"] == "reaction" && body["reaction"]["emoji"] == ""
        }
        .to_return(
          status: 200,
          body: JSON.generate({"messaging_product" => "whatsapp", "messages" => [{"id" => "wamid.unreact123"}]}),
          headers: {"Content-Type" => "application/json"}
        )

      subject.remove_reaction(channel_id: "15551234567", message_id: "wamid.orig123", emoji: "\u{1F44D}")
      expect(stub).to have_been_requested
    end
  end

  describe "#open_dm" do
    it "returns the user_id directly" do
      expect(subject.open_dm("15551234567")).to eq("15551234567")
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

    it "raises NotSupportedError for message_history" do
      expect { subject.fetch_messages(channel_id: "C1") }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "does not support edit_messages capability" do
      expect(subject.supports?(:edit_messages)).to be false
    end

    it "does not support delete_messages capability" do
      expect(subject.supports?(:delete_messages)).to be false
    end

    it "does not support ephemeral_messages capability" do
      expect(subject.supports?(:ephemeral_messages)).to be false
    end

    it "does not support modals capability" do
      expect(subject.supports?(:modals)).to be false
    end

    it "does not support streaming_edit capability" do
      expect(subject.supports?(:streaming_edit)).to be false
    end

    it "does not support threads capability" do
      expect(subject.supports?(:threads)).to be false
    end

    it "does not support message_history capability" do
      expect(subject.supports?(:message_history)).to be false
    end

    it "does not support typing_indicator capability" do
      expect(subject.supports?(:typing_indicator)).to be false
    end

    it "supports direct_messages capability" do
      expect(subject.supports?(:direct_messages)).to be true
    end

    it "supports file_uploads capability" do
      expect(subject.supports?(:file_uploads)).to be true
    end

    it "supports reactions capability" do
      expect(subject.supports?(:reactions)).to be true
    end
  end

  describe "#render" do
    it "renders a card as interactive payload" do
      card = ChatSDK.card(title: "Test") do
        text "Body"
        actions do
          button "Click", id: "btn_click", style: :primary
        end
      end
      msg = ChatSDK::PostableMessage.new(card: card, text: "Test")

      result = subject.render(msg)
      expect(result).to be_a(Hash)
      expect(result[:type]).to eq("interactive")
      expect(result[:interactive]).to be_a(Hash)
    end

    it "renders plain text as-is" do
      msg = ChatSDK::PostableMessage.new(text: "Plain text")
      result = subject.render(msg)
      expect(result).to eq("Plain text")
    end
  end

  describe ChatSDK::WhatsApp::InteractiveRenderer do
    let(:renderer) { described_class.new }

    describe "#render" do
      it "renders a text node" do
        node = ChatSDK::Cards::Node.new(:text, attributes: {content: "Hello world"})
        result = renderer.render(node)

        expect(result).to be_a(Hash)
        expect(result[:text]).to eq("Hello world")
      end

      it "renders a card with title and buttons as interactive button message" do
        card = ChatSDK.card(title: "Incident #4821") do
          text "Details here"
          actions do
            button "Acknowledge", id: "incident:ack", style: :primary
          end
        end
        result = renderer.render(card)

        expect(result[:type]).to eq("interactive")
        interactive = result[:interactive]
        expect(interactive["type"]).to eq("button")
        expect(interactive["header"]["text"]).to eq("Incident #4821")
        expect(interactive["action"]["buttons"].first["reply"]["id"]).to eq("incident:ack")
      end

      it "skips link buttons (WhatsApp reply buttons cannot have URLs)" do
        card = ChatSDK.card(title: "Links") do
          actions do
            link_button "View", url: "https://example.com"
          end
        end
        result = renderer.render(card)

        # Falls back to text since no reply buttons remain
        expect(result[:text]).to be_a(String)
        expect(result[:text]).to include("Links")
      end

      it "truncates button titles to 20 characters" do
        card = ChatSDK.card(title: "Test") do
          actions do
            button "This is a very long button title", id: "btn_long"
          end
        end
        result = renderer.render(card)

        interactive = result[:interactive]
        button_title = interactive["action"]["buttons"].first["reply"]["title"]
        expect(button_title.length).to be <= 20
      end

      it "falls back to text for more than 3 buttons" do
        card = ChatSDK.card(title: "Many Buttons") do
          actions do
            button "One", id: "btn1"
            button "Two", id: "btn2"
            button "Three", id: "btn3"
            button "Four", id: "btn4"
          end
        end
        result = renderer.render(card)

        expect(result[:text]).to be_a(String)
      end

      it "renders fields as text" do
        card = ChatSDK.card do
          fields do
            field "Status", "Active"
            field "Severity", "SEV1"
          end
        end
        result = renderer.render(card)

        expect(result[:text]).to include("Status: Active")
        expect(result[:text]).to include("Severity: SEV1")
      end
    end
  end

  describe "API error handling" do
    it "raises RateLimitedError on 429" do
      stub_request(:post, %r{graph\.facebook\.com/v21\.0/#{phone_number_id}/messages})
        .to_return(
          status: 429,
          body: JSON.generate({"error" => {"message" => "Rate limit hit", "code" => 80007}}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.post_message(channel_id: "15551234567", message: "Hello!") }
        .to raise_error(ChatSDK::RateLimitedError)
    end

    it "raises PlatformError on other errors" do
      stub_request(:post, %r{graph\.facebook\.com/v21\.0/#{phone_number_id}/messages})
        .to_return(
          status: 400,
          body: JSON.generate({"error" => {"message" => "Invalid OAuth access token", "code" => 190}}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.post_message(channel_id: "15551234567", message: "Hello!") }
        .to raise_error(ChatSDK::PlatformError, /Invalid OAuth/)
    end
  end
end
