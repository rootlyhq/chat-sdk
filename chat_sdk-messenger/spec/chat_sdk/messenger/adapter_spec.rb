# frozen_string_literal: true

require_relative "../../spec_helper"
require "rack"

RSpec.describe ChatSDK::Messenger::Adapter do
  subject do
    described_class.new(
      app_secret: app_secret,
      page_access_token: page_access_token,
      verify_token: verify_token
    )
  end

  let(:app_secret) { "test_app_secret_123" }
  let(:page_access_token) { "EAABsbCS1iZAIBAKx7example" }
  let(:verify_token) { "my_verify_token" }

  it_behaves_like "a chat_sdk platform adapter"

  describe "#initialize" do
    it "raises ConfigurationError without app_secret" do
      expect { described_class.new(app_secret: nil, page_access_token: page_access_token) }
        .to raise_error(ChatSDK::ConfigurationError, /app_secret required/)
    end

    it "raises ConfigurationError without page_access_token" do
      expect { described_class.new(app_secret: app_secret, page_access_token: nil) }
        .to raise_error(ChatSDK::ConfigurationError, /page_access_token required/)
    end

    it "falls back to environment variables" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("FACEBOOK_APP_SECRET").and_return("env-secret")
      allow(ENV).to receive(:[]).with("FACEBOOK_PAGE_ACCESS_TOKEN").and_return("env-token")
      allow(ENV).to receive(:[]).with("FACEBOOK_VERIFY_TOKEN").and_return("env-verify")

      adapter = described_class.new
      expect(adapter.name).to eq(:messenger)
    end
  end

  describe "#name" do
    it "returns :messenger" do
      expect(subject.name).to eq(:messenger)
    end
  end

  describe "#client" do
    it "returns an ApiClient" do
      expect(subject.client).to be_a(ChatSDK::Messenger::ApiClient)
    end
  end

  describe "#mention" do
    it "returns the user_id as-is" do
      expect(subject.mention("123456")).to eq("123456")
    end
  end

  describe "#verify_request!" do
    def build_request(body, headers = {})
      env = Rack::MockRequest.env_for(
        "/webhooks/messenger",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json",
        **headers
      )
      Rack::Request.new(env)
    end

    it "accepts a valid HMAC-SHA256 signature" do
      body = '{"object":"page","entry":[]}'
      signature = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", app_secret, body)}"
      request = build_request(body, "HTTP_X_HUB_SIGNATURE_256" => signature)

      expect(subject.verify_request!(request)).to be(true)
    end

    it "rejects an invalid signature" do
      body = '{"object":"page","entry":[]}'
      request = build_request(body, "HTTP_X_HUB_SIGNATURE_256" => "sha256=invalid")

      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Invalid Facebook signature/)
    end

    it "rejects missing signature header" do
      body = '{"object":"page","entry":[]}'
      request = build_request(body)

      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Missing Facebook signature/)
    end
  end

  describe "#ack_response" do
    it "returns challenge for valid GET webhook verification" do
      env = Rack::MockRequest.env_for(
        "/webhooks/messenger?hub.mode=subscribe&hub.verify_token=#{verify_token}&hub.challenge=CHALLENGE_STRING",
        method: "GET"
      )
      request = Rack::Request.new(env)

      result = subject.ack_response(request)
      expect(result).to eq([200, {}, ["CHALLENGE_STRING"]])
    end

    it "returns nil for GET with wrong verify_token" do
      env = Rack::MockRequest.env_for(
        "/webhooks/messenger?hub.mode=subscribe&hub.verify_token=wrong_token&hub.challenge=CHALLENGE",
        method: "GET"
      )
      request = Rack::Request.new(env)

      expect(subject.ack_response(request)).to be_nil
    end

    it "returns nil for GET with wrong mode" do
      env = Rack::MockRequest.env_for(
        "/webhooks/messenger?hub.mode=unsubscribe&hub.verify_token=#{verify_token}&hub.challenge=CHALLENGE",
        method: "GET"
      )
      request = Rack::Request.new(env)

      expect(subject.ack_response(request)).to be_nil
    end

    it "returns nil for POST requests" do
      env = Rack::MockRequest.env_for(
        "/webhooks/messenger",
        method: "POST",
        input: '{"object":"page"}'
      )
      request = Rack::Request.new(env)

      expect(subject.ack_response(request)).to be_nil
    end
  end

  describe "#parse_events" do
    def build_request(body)
      env = Rack::MockRequest.env_for(
        "/webhooks/messenger",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json"
      )
      Rack::Request.new(env)
    end

    context "text message" do
      it "parses into DirectMessage event" do
        payload = {
          "object" => "page",
          "entry" => [{
            "id" => "PAGE_ID",
            "time" => 1_458_692_752_478,
            "messaging" => [{
              "sender" => {"id" => "USER_123"},
              "recipient" => {"id" => "PAGE_ID"},
              "timestamp" => 1_458_692_752_478,
              "message" => {
                "mid" => "mid.1457764197618:41d102a3e1ae206a38",
                "text" => "Hello, bot!"
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
        expect(event.message.id).to eq("mid.1457764197618:41d102a3e1ae206a38")
        expect(event.message.author.id).to eq("USER_123")
        expect(event.channel_id).to eq("USER_123")
        expect(event.thread_id).to eq("messenger:USER_123")
        expect(event.platform).to eq(:messenger)
        expect(event.adapter_name).to eq(:messenger)
      end
    end

    context "postback" do
      it "parses into Action event" do
        payload = {
          "object" => "page",
          "entry" => [{
            "id" => "PAGE_ID",
            "time" => 1_458_692_752_478,
            "messaging" => [{
              "sender" => {"id" => "USER_456"},
              "recipient" => {"id" => "PAGE_ID"},
              "timestamp" => 1_458_692_752_478,
              "postback" => {
                "title" => "Acknowledge",
                "payload" => "incident:ack"
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
        expect(event.user.id).to eq("USER_456")
        expect(event.channel_id).to eq("USER_456")
        expect(event.thread_id).to eq("messenger:USER_456")
        expect(event.platform).to eq(:messenger)
      end
    end

    context "message with attachments" do
      it "extracts attachment URLs" do
        payload = {
          "object" => "page",
          "entry" => [{
            "id" => "PAGE_ID",
            "time" => 1_458_692_752_478,
            "messaging" => [{
              "sender" => {"id" => "USER_789"},
              "recipient" => {"id" => "PAGE_ID"},
              "timestamp" => 1_458_692_752_478,
              "message" => {
                "mid" => "mid.attachment123",
                "attachments" => [{
                  "type" => "image",
                  "payload" => {
                    "url" => "https://example.com/photo.jpg"
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
        expect(event.message.text).to include("https://example.com/photo.jpg")
      end
    end

    context "non-page object" do
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

    context "multiple messaging events" do
      it "parses all events" do
        payload = {
          "object" => "page",
          "entry" => [{
            "id" => "PAGE_ID",
            "messaging" => [
              {
                "sender" => {"id" => "USER_1"},
                "recipient" => {"id" => "PAGE_ID"},
                "message" => {"mid" => "mid.1", "text" => "First"}
              },
              {
                "sender" => {"id" => "USER_2"},
                "recipient" => {"id" => "PAGE_ID"},
                "message" => {"mid" => "mid.2", "text" => "Second"}
              }
            ]
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
      stub_request(:post, %r{graph\.facebook\.com/v21\.0/me/messages})
        .to_return(
          status: 200,
          body: JSON.generate({"recipient_id" => "USER_123", "message_id" => "mid.resp123"}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.post_message(channel_id: "USER_123", message: "Hello!")
      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("mid.resp123")
      expect(result.platform).to eq(:messenger)
    end

    it "sends a card message as template" do
      stub_request(:post, %r{graph\.facebook\.com/v21\.0/me/messages})
        .with { |req|
          body = JSON.parse(req.body)
          body["message"]["attachment"].is_a?(Hash)
        }
        .to_return(
          status: 200,
          body: JSON.generate({"recipient_id" => "USER_123", "message_id" => "mid.card123"}),
          headers: {"Content-Type" => "application/json"}
        )

      card = ChatSDK.card(title: "Incident #4821") do
        text "Details"
        actions do
          button "Ack", id: "incident:ack", style: :primary, value: "4821"
        end
      end

      result = subject.post_message(
        channel_id: "USER_123",
        message: ChatSDK::PostableMessage.new(card: card, text: "Incident Update")
      )
      expect(result.id).to eq("mid.card123")
    end
  end

  describe "#open_dm" do
    it "returns the user_id directly" do
      expect(subject.open_dm("USER_123")).to eq("USER_123")
    end
  end

  describe "#start_typing" do
    it "sends typing_on action" do
      stub = stub_request(:post, %r{graph\.facebook\.com/v21\.0/me/messages})
        .with { |req|
          body = JSON.parse(req.body)
          body["sender_action"] == "typing_on"
        }
        .to_return(
          status: 200,
          body: JSON.generate({"recipient_id" => "USER_123"}),
          headers: {"Content-Type" => "application/json"}
        )

      subject.start_typing(channel_id: "USER_123")
      expect(stub).to have_been_requested
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

    it "raises NotSupportedError for reactions" do
      expect { subject.add_reaction(channel_id: "C1", message_id: "M1", emoji: "thumbsup") }
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

    it "does not support reactions capability" do
      expect(subject.supports?(:reactions)).to be false
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
  end

  describe "#render" do
    it "renders a card as template payload" do
      card = ChatSDK.card(title: "Test") do
        text "Body"
        actions do
          button "Click", id: "btn_click", style: :primary
        end
      end
      msg = ChatSDK::PostableMessage.new(card: card, text: "Test")

      result = subject.render(msg)
      expect(result).to be_a(Hash)
      expect(result[:attachment]).to be_a(Hash)
    end

    it "renders plain text as-is" do
      msg = ChatSDK::PostableMessage.new(text: "Plain text")
      result = subject.render(msg)
      expect(result).to eq("Plain text")
    end
  end

  describe ChatSDK::Messenger::TemplateRenderer do
    let(:renderer) { described_class.new }

    describe "#render" do
      it "renders a text node" do
        node = ChatSDK::Cards::Node.new(:text, attributes: {content: "Hello world"})
        result = renderer.render(node)

        expect(result).to be_a(Hash)
        expect(result[:text]).to eq("Hello world")
      end

      it "renders a card with title and buttons as Generic Template" do
        card = ChatSDK.card(title: "Incident #4821") do
          text "Details here"
          actions do
            button "Acknowledge", id: "incident:ack", style: :primary
          end
        end
        result = renderer.render(card)

        expect(result[:attachment]).to be_a(Hash)
        payload = result[:attachment]["payload"]
        expect(payload["template_type"]).to eq("generic")
        expect(payload["elements"].first["title"]).to eq("Incident #4821")
        expect(payload["elements"].first["buttons"].first["type"]).to eq("postback")
        expect(payload["elements"].first["buttons"].first["payload"]).to eq("incident:ack")
      end

      it "renders link buttons as web_url type" do
        card = ChatSDK.card(title: "Links") do
          actions do
            link_button "View", url: "https://example.com"
          end
        end
        result = renderer.render(card)

        payload = result[:attachment]["payload"]
        button = payload["elements"].first["buttons"].first
        expect(button["type"]).to eq("web_url")
        expect(button["url"]).to eq("https://example.com")
      end

      it "truncates button titles to 20 characters" do
        card = ChatSDK.card(title: "Test") do
          actions do
            button "This is a very long button title", id: "btn_long"
          end
        end
        result = renderer.render(card)

        payload = result[:attachment]["payload"]
        button = payload["elements"].first["buttons"].first
        expect(button["title"].length).to be <= 20
      end

      it "limits to 3 buttons maximum" do
        card = ChatSDK.card(title: "Many Buttons") do
          actions do
            button "One", id: "btn1"
            button "Two", id: "btn2"
            button "Three", id: "btn3"
            button "Four", id: "btn4"
          end
        end
        result = renderer.render(card)

        payload = result[:attachment]["payload"]
        expect(payload["elements"].first["buttons"].length).to eq(3)
      end

      it "falls back to text for cards with more than 3 buttons and no title" do
        card = ChatSDK.card do
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
      stub_request(:post, %r{graph\.facebook\.com/v21\.0/me/messages})
        .to_return(
          status: 429,
          body: JSON.generate({"error" => {"message" => "Rate limit hit", "code" => 4}}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.post_message(channel_id: "USER_123", message: "Hello!") }
        .to raise_error(ChatSDK::RateLimitedError)
    end

    it "raises PlatformError on other errors" do
      stub_request(:post, %r{graph\.facebook\.com/v21\.0/me/messages})
        .to_return(
          status: 400,
          body: JSON.generate({"error" => {"message" => "Invalid OAuth access token", "code" => 190}}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.post_message(channel_id: "USER_123", message: "Hello!") }
        .to raise_error(ChatSDK::PlatformError, /Invalid OAuth/)
    end
  end
end
