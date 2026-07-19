# frozen_string_literal: true

require_relative "../../spec_helper"
require "rack"

RSpec.describe ChatSDK::X::Adapter do
  subject do
    described_class.new(
      access_token: access_token,
      consumer_secret: consumer_secret,
      user_id: user_id
    )
  end

  let(:access_token) { "test-access-token" }
  let(:consumer_secret) { "test-consumer-secret" }
  let(:user_id) { "test-user-id-12345" }

  it_behaves_like "a chat_sdk platform adapter"

  describe "#initialize" do
    it "raises ConfigurationError without access_token" do
      expect { described_class.new(access_token: nil, consumer_secret: consumer_secret) }
        .to raise_error(ChatSDK::ConfigurationError, /access_token required/)
    end

    it "raises ConfigurationError without consumer_secret" do
      expect { described_class.new(access_token: access_token, consumer_secret: nil) }
        .to raise_error(ChatSDK::ConfigurationError, /consumer_secret required/)
    end

    it "falls back to environment variables" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("X_ACCESS_TOKEN").and_return("env-token")
      allow(ENV).to receive(:[]).with("X_CONSUMER_SECRET").and_return("env-secret")
      allow(ENV).to receive(:[]).with("X_USER_ID").and_return("env-user-id")

      adapter = described_class.new
      expect(adapter.name).to eq(:x)
    end
  end

  describe "#name" do
    it "returns :x" do
      expect(subject.name).to eq(:x)
    end
  end

  describe "#client" do
    it "returns an ApiClient" do
      expect(subject.client).to be_a(ChatSDK::X::ApiClient)
    end
  end

  describe "#mention" do
    it "formats an X mention with @" do
      expect(subject.mention("rootly")).to eq("@rootly")
    end
  end

  describe "#verify_request!" do
    def build_signed_request(body)
      signature = "sha256=#{Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", consumer_secret, body))}"

      env = Rack::MockRequest.env_for(
        "/webhooks/x",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_TWITTER_WEBHOOKS_SIGNATURE" => signature
      )
      Rack::Request.new(env)
    end

    def build_request(body, signature: "sha256=invalid")
      env = Rack::MockRequest.env_for(
        "/webhooks/x",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_TWITTER_WEBHOOKS_SIGNATURE" => signature
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
      request = build_request(body, signature: "sha256=invalidhash")
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Invalid X signature/)
    end

    it "rejects missing signature header" do
      env = Rack::MockRequest.env_for(
        "/webhooks/x",
        :method => "POST",
        :input => '{"test":"data"}',
        "CONTENT_TYPE" => "application/json"
      )
      request = Rack::Request.new(env)
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Missing X signature/)
    end
  end

  describe "#ack_response" do
    it "returns CRC challenge response for GET with crc_token" do
      env = Rack::MockRequest.env_for(
        "/webhooks/x?crc_token=test-crc-token",
        method: "GET"
      )
      request = Rack::Request.new(env)
      result = subject.ack_response(request)

      expect(result).not_to be_nil
      status, headers, body = result
      expect(status).to eq(200)
      expect(headers).to eq({"content-type" => "application/json"})

      parsed = JSON.parse(body.first)
      expected_token = "sha256=#{Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", consumer_secret, "test-crc-token"))}"
      expect(parsed["response_token"]).to eq(expected_token)
    end

    it "returns nil for GET without crc_token" do
      env = Rack::MockRequest.env_for("/webhooks/x", method: "GET")
      request = Rack::Request.new(env)
      expect(subject.ack_response(request)).to be_nil
    end

    it "returns nil for POST requests" do
      env = Rack::MockRequest.env_for(
        "/webhooks/x",
        :method => "POST",
        :input => '{"type":"event"}',
        "CONTENT_TYPE" => "application/json"
      )
      request = Rack::Request.new(env)
      expect(subject.ack_response(request)).to be_nil
    end
  end

  describe "#parse_events" do
    def build_request(body)
      env = Rack::MockRequest.env_for(
        "/webhooks/x",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json"
      )
      Rack::Request.new(env)
    end

    context "mention events" do
      it "parses tweet mention into Mention event" do
        payload = {
          "tweet_create_events" => [
            {
              "id" => "tweet-123",
              "text" => "@mybot hello there",
              "author_id" => "user-456",
              "conversation_id" => "conv-789"
            }
          ]
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Mention)
        expect(event.message.id).to eq("tweet-123")
        expect(event.message.text).to eq("@mybot hello there")
        expect(event.message.author.id).to eq("user-456")
        expect(event.thread_id).to eq("x:post:conv-789")
        expect(event.channel_id).to eq("user-456")
        expect(event.platform).to eq(:x)
        expect(event.adapter_name).to eq(:x)
      end

      it "skips mentions from the bot itself" do
        payload = {
          "tweet_create_events" => [
            {
              "id" => "tweet-999",
              "text" => "I am the bot",
              "author_id" => user_id,
              "conversation_id" => "conv-999"
            }
          ]
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events).to be_empty
      end
    end

    context "direct message events" do
      it "parses DM into DirectMessage event" do
        payload = {
          "direct_message_events" => [
            {
              "id" => "dm-123",
              "sender_id" => "user-789",
              "text" => "Hello via DM"
            }
          ]
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::DirectMessage)
        expect(event.message.id).to eq("dm-123")
        expect(event.message.text).to eq("Hello via DM")
        expect(event.message.author.id).to eq("user-789")
        expect(event.thread_id).to eq("x:dm:user-789")
        expect(event.channel_id).to eq("user-789")
        expect(event.platform).to eq(:x)
        expect(event.adapter_name).to eq(:x)
      end

      it "skips DMs from the bot itself" do
        payload = {
          "direct_message_events" => [
            {
              "id" => "dm-999",
              "sender_id" => user_id,
              "text" => "Bot sent this"
            }
          ]
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
    context "tweet (non-DM)" do
      it "sends a new tweet" do
        stub_request(:post, "https://api.x.com/2/tweets")
          .to_return(
            status: 200,
            body: JSON.generate({"data" => {"id" => "tweet-new-1"}}),
            headers: {"Content-Type" => "application/json"}
          )

        result = subject.post_message(channel_id: "user-456", message: "Hello X!")
        expect(result).to be_a(ChatSDK::Message)
        expect(result.id).to eq("tweet-new-1")
        expect(result.platform).to eq(:x)
        expect(result.thread_id).to eq("x:post:tweet-new-1")
      end

      it "sends a reply tweet when thread_id is present" do
        stub_request(:post, "https://api.x.com/2/tweets")
          .with { |req|
            body = JSON.parse(req.body)
            body["reply"] && body["reply"]["in_reply_to_tweet_id"] == "original-tweet"
          }
          .to_return(
            status: 200,
            body: JSON.generate({"data" => {"id" => "tweet-reply-1"}}),
            headers: {"Content-Type" => "application/json"}
          )

        result = subject.post_message(channel_id: "original-tweet", message: "Reply!", thread_id: "x:post:conv-1")
        expect(result).to be_a(ChatSDK::Message)
        expect(result.id).to eq("tweet-reply-1")
      end
    end

    context "direct message" do
      it "sends a DM when thread_id starts with x:dm:" do
        stub_request(:post, "https://api.x.com/2/dm_conversations/with/user-789/messages")
          .to_return(
            status: 200,
            body: JSON.generate({"dm_event" => {"id" => "dm-new-1"}}),
            headers: {"Content-Type" => "application/json"}
          )

        result = subject.post_message(channel_id: "user-789", message: "DM text", thread_id: "x:dm:user-789")
        expect(result).to be_a(ChatSDK::Message)
        expect(result.id).to eq("dm-new-1")
        expect(result.thread_id).to eq("x:dm:user-789")
      end
    end
  end

  describe "#add_reaction" do
    it "likes a tweet" do
      stub_request(:post, "https://api.x.com/2/users/#{user_id}/likes")
        .with(body: JSON.generate({"tweet_id" => "tweet-123"}))
        .to_return(
          status: 200,
          body: JSON.generate({"data" => {"liked" => true}}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.add_reaction(channel_id: "ch1", message_id: "tweet-123", emoji: "heart") }
        .not_to raise_error
    end
  end

  describe "#remove_reaction" do
    it "unlikes a tweet" do
      stub_request(:delete, "https://api.x.com/2/users/#{user_id}/likes/tweet-123")
        .to_return(
          status: 200,
          body: JSON.generate({"data" => {"liked" => false}}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.remove_reaction(channel_id: "ch1", message_id: "tweet-123", emoji: "heart") }
        .not_to raise_error
    end
  end

  describe "#open_dm" do
    it "returns the user_id directly" do
      expect(subject.open_dm("user-789")).to eq("user-789")
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

    it "does not support edit_messages capability" do
      expect(subject.supports?(:edit_messages)).to be false
    end

    it "does not support modals capability" do
      expect(subject.supports?(:modals)).to be false
    end

    it "does not support typing_indicator capability" do
      expect(subject.supports?(:typing_indicator)).to be false
    end

    it "supports direct_messages capability" do
      expect(subject.supports?(:direct_messages)).to be true
    end

    it "supports reactions capability" do
      expect(subject.supports?(:reactions)).to be true
    end
  end
end
