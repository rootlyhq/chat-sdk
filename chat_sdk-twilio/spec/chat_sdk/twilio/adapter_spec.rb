# frozen_string_literal: true

require_relative "../../spec_helper"
require "rack"
require "openssl"
require "base64"

RSpec.describe ChatSDK::Twilio::Adapter do
  subject do
    described_class.new(
      account_sid: account_sid,
      auth_token: auth_token,
      phone_number: phone_number,
      webhook_url: webhook_url
    )
  end

  let(:account_sid) { "test-account-sid-not-real" }
  let(:auth_token) { "test_auth_token_secret" }
  let(:phone_number) { "+15551234567" }
  let(:webhook_url) { "https://example.com/webhooks/twilio" }

  it_behaves_like "a chat_sdk platform adapter"

  describe "#initialize" do
    it "raises ConfigurationError without account_sid" do
      expect { described_class.new(account_sid: nil, auth_token: auth_token, phone_number: phone_number) }
        .to raise_error(ChatSDK::ConfigurationError, /account_sid required/)
    end

    it "raises ConfigurationError without auth_token" do
      expect { described_class.new(account_sid: account_sid, auth_token: nil, phone_number: phone_number) }
        .to raise_error(ChatSDK::ConfigurationError, /auth_token required/)
    end

    it "raises ConfigurationError without phone_number or messaging_service_sid" do
      expect { described_class.new(account_sid: account_sid, auth_token: auth_token, phone_number: nil, messaging_service_sid: nil) }
        .to raise_error(ChatSDK::ConfigurationError, /phone_number or messaging_service_sid required/)
    end

    it "accepts messaging_service_sid instead of phone_number" do
      adapter = described_class.new(
        account_sid: account_sid,
        auth_token: auth_token,
        messaging_service_sid: "MG1234567890"
      )
      expect(adapter.name).to eq(:twilio)
    end

    it "falls back to environment variables" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TWILIO_ACCOUNT_SID").and_return("env-sid")
      allow(ENV).to receive(:[]).with("TWILIO_AUTH_TOKEN").and_return("env-token")
      allow(ENV).to receive(:[]).with("TWILIO_PHONE_NUMBER").and_return("+15559999999")
      allow(ENV).to receive(:[]).with("TWILIO_MESSAGING_SERVICE_SID").and_return(nil)

      adapter = described_class.new
      expect(adapter.name).to eq(:twilio)
    end
  end

  describe "#name" do
    it "returns :twilio" do
      expect(subject.name).to eq(:twilio)
    end
  end

  describe "#client" do
    it "returns an ApiClient" do
      expect(subject.client).to be_a(ChatSDK::Twilio::ApiClient)
    end
  end

  describe "#mention" do
    it "returns the phone number as-is" do
      expect(subject.mention("+15559876543")).to eq("+15559876543")
    end
  end

  describe "#verify_request!" do
    def compute_signature(url, params)
      data = url + params.sort.join
      digest = OpenSSL::HMAC.digest("SHA1", auth_token, data)
      Base64.strict_encode64(digest)
    end

    def build_request(body, headers = {})
      env = Rack::MockRequest.env_for(
        "/webhooks/twilio",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/x-www-form-urlencoded",
        **headers
      )
      Rack::Request.new(env)
    end

    it "accepts a valid Twilio signature" do
      params = {"From" => "+15551111111", "Body" => "Hello", "MessageSid" => "SM123"}
      body = Rack::Utils.build_query(params)
      sig = compute_signature(webhook_url, params)

      request = build_request(body, "HTTP_X_TWILIO_SIGNATURE" => sig)
      expect(subject.verify_request!(request)).to be(true)
    end

    it "rejects an invalid Twilio signature" do
      params = {"From" => "+15551111111", "Body" => "Hello", "MessageSid" => "SM123"}
      body = Rack::Utils.build_query(params)

      request = build_request(body, "HTTP_X_TWILIO_SIGNATURE" => "invalid_signature")
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Invalid Twilio signature/)
    end

    it "rejects missing signature header" do
      body = "From=%2B15551111111&Body=Hello&MessageSid=SM123"
      request = build_request(body)
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Missing Twilio signature/)
    end
  end

  describe "#ack_response" do
    it "always returns nil" do
      env = Rack::MockRequest.env_for("/webhooks/twilio", method: "POST", input: "")
      request = Rack::Request.new(env)
      expect(subject.ack_response(request)).to be_nil
    end
  end

  describe "#parse_events" do
    def build_request(body)
      env = Rack::MockRequest.env_for(
        "/webhooks/twilio",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      )
      Rack::Request.new(env)
    end

    context "inbound SMS" do
      it "parses into DirectMessage event" do
        params = {
          "MessageSid" => "SM1234567890",
          "From" => "+15551111111",
          "To" => "+15551234567",
          "Body" => "Hello bot"
        }
        body = Rack::Utils.build_query(params)
        request = build_request(body)
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::DirectMessage)
        expect(event.message.id).to eq("SM1234567890")
        expect(event.message.text).to eq("Hello bot")
        expect(event.message.author.id).to eq("+15551111111")
        expect(event.channel_id).to eq("+15551234567")
        expect(event.platform).to eq(:twilio)
        expect(event.adapter_name).to eq(:twilio)
      end
    end

    context "inbound MMS with media" do
      it "extracts media attachments" do
        params = {
          "MessageSid" => "SM9876543210",
          "From" => "+15552222222",
          "To" => "+15551234567",
          "Body" => "Check this out",
          "NumMedia" => "2",
          "MediaUrl0" => "https://api.twilio.com/media/img1.jpg",
          "MediaContentType0" => "image/jpeg",
          "MediaUrl1" => "https://api.twilio.com/media/doc1.pdf",
          "MediaContentType1" => "application/pdf"
        }
        body = Rack::Utils.build_query(params)
        request = build_request(body)
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::DirectMessage)
        expect(event.message.text).to include("Check this out")
        expect(event.message.text).to include("https://api.twilio.com/media/img1.jpg")
        expect(event.message.text).to include("https://api.twilio.com/media/doc1.pdf")
        expect(event.message.raw["NumMedia"]).to eq("2")
      end
    end

    context "MMS with media only (no body)" do
      it "includes media URLs as text" do
        params = {
          "MessageSid" => "SM5555555555",
          "From" => "+15553333333",
          "To" => "+15551234567",
          "Body" => "",
          "NumMedia" => "1",
          "MediaUrl0" => "https://api.twilio.com/media/photo.jpg",
          "MediaContentType0" => "image/jpeg"
        }
        body = Rack::Utils.build_query(params)
        request = build_request(body)
        events = subject.parse_events(request)

        event = events.first
        expect(event.message.text).to eq("https://api.twilio.com/media/photo.jpg")
      end
    end

    context "empty body" do
      it "returns empty array" do
        request = build_request("")
        events = subject.parse_events(request)
        expect(events).to be_empty
      end
    end
  end

  describe "#post_message" do
    let(:api_url) { "https://api.twilio.com/2010-04-01/Accounts/#{account_sid}/Messages.json" }

    it "sends an SMS message" do
      stub_request(:post, api_url)
        .to_return(
          status: 201,
          body: JSON.generate({
            "sid" => "SM0001",
            "body" => "Hello!",
            "from" => phone_number,
            "to" => "+15559876543",
            "status" => "queued"
          }),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.post_message(channel_id: "+15559876543", message: "Hello!")
      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("SM0001")
      expect(result.text).to eq("Hello!")
      expect(result.platform).to eq(:twilio)
    end

    it "sends a card as plain text fallback" do
      stub_request(:post, api_url)
        .to_return(
          status: 201,
          body: JSON.generate({
            "sid" => "SM0002",
            "body" => "Incident Update",
            "from" => phone_number,
            "to" => "+15559876543",
            "status" => "queued"
          }),
          headers: {"Content-Type" => "application/json"}
        )

      card = ChatSDK.card do
        text "Incident Update"
        actions do
          button "Ack", id: "incident:ack", style: :primary, value: "4821"
        end
      end

      result = subject.post_message(
        channel_id: "+15559876543",
        message: ChatSDK::PostableMessage.new(card: card, text: "Incident Update")
      )
      expect(result.id).to eq("SM0002")
    end

    it "ignores thread_id (SMS has no threads)" do
      stub = stub_request(:post, api_url)
        .to_return(
          status: 201,
          body: JSON.generate({
            "sid" => "SM0003",
            "body" => "Reply!",
            "from" => phone_number,
            "to" => "+15559876543",
            "status" => "queued"
          }),
          headers: {"Content-Type" => "application/json"}
        )

      subject.post_message(channel_id: "+15559876543", message: "Reply!", thread_id: "SM0001")
      expect(stub).to have_been_requested
    end
  end

  describe "#upload_file" do
    it "raises PlatformError explaining binary upload is not supported" do
      expect { subject.upload_file(channel_id: "+15559876543", io: StringIO.new("data"), filename: "test.txt") }
        .to raise_error(ChatSDK::PlatformError, /MediaUrl/)
    end
  end

  describe "#open_dm" do
    it "returns the phone number directly" do
      expect(subject.open_dm("+15559876543")).to eq("+15559876543")
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

    it "raises NotSupportedError for typing indicator" do
      expect { subject.start_typing(channel_id: "C1") }
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

    it "does not support threads capability" do
      expect(subject.supports?(:threads)).to be false
    end

    it "does not support streaming_edit capability" do
      expect(subject.supports?(:streaming_edit)).to be false
    end

    it "does not support typing_indicator capability" do
      expect(subject.supports?(:typing_indicator)).to be false
    end

    it "does not support message_history capability" do
      expect(subject.supports?(:message_history)).to be false
    end

    it "supports direct_messages capability" do
      expect(subject.supports?(:direct_messages)).to be true
    end

    it "supports file_uploads capability" do
      expect(subject.supports?(:file_uploads)).to be true
    end
  end

  describe "#render" do
    it "renders a card as plain text fallback" do
      card = ChatSDK.card do
        text "Hello"
      end
      msg = ChatSDK::PostableMessage.new(card: card, text: "Hello")

      result = subject.render(msg)
      expect(result).to include("Hello")
    end

    it "renders plain text as-is" do
      msg = ChatSDK::PostableMessage.new(text: "Plain text")
      result = subject.render(msg)
      expect(result).to eq("Plain text")
    end
  end

  describe "API error handling" do
    let(:api_url) { "https://api.twilio.com/2010-04-01/Accounts/#{account_sid}/Messages.json" }

    it "raises RateLimitedError on 429" do
      stub_request(:post, api_url)
        .to_return(
          status: 429,
          body: JSON.generate({"message" => "Too Many Requests"}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.post_message(channel_id: "+15559876543", message: "Hello!") }
        .to raise_error(ChatSDK::RateLimitedError)
    end

    it "raises PlatformError on other errors" do
      stub_request(:post, api_url)
        .to_return(
          status: 400,
          body: JSON.generate({"message" => "The 'To' number is not a valid phone number."}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.post_message(channel_id: "invalid", message: "Hello!") }
        .to raise_error(ChatSDK::PlatformError, /not a valid phone number/)
    end
  end

  describe ChatSDK::Twilio::Signature do
    describe ".verify!" do
      let(:url) { "https://example.com/webhooks/twilio" }
      let(:params) { {"From" => "+15551111111", "Body" => "Hello"} }

      it "returns true for a valid signature" do
        data = url + params.sort.join
        digest = OpenSSL::HMAC.digest("SHA1", auth_token, data)
        signature = Base64.strict_encode64(digest)

        expect(described_class.verify!(auth_token, url, params, signature)).to be(true)
      end

      it "raises SignatureVerificationError for an invalid signature" do
        expect { described_class.verify!(auth_token, url, params, "bad_sig") }
          .to raise_error(ChatSDK::SignatureVerificationError, /Invalid Twilio signature/)
      end
    end
  end
end
