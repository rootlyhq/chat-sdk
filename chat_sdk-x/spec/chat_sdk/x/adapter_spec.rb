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
    it "raises ConfigurationError without access_token or client_id+refresh_token" do
      expect { described_class.new(access_token: nil, consumer_secret: consumer_secret) }
        .to raise_error(ChatSDK::ConfigurationError, /access_token or client_id \+ refresh_token/)
    end

    it "raises ConfigurationError without consumer_secret" do
      expect { described_class.new(access_token: access_token, consumer_secret: nil) }
        .to raise_error(ChatSDK::ConfigurationError, /consumer_secret required/)
    end

    it "accepts client_id + refresh_token without access_token" do
      adapter = described_class.new(
        consumer_secret: consumer_secret,
        client_id: "my-client-id",
        refresh_token: "my-refresh-token"
      )
      expect(adapter.name).to eq(:x)
    end

    it "raises ConfigurationError with client_id but no refresh_token and no access_token" do
      expect {
        described_class.new(consumer_secret: consumer_secret, client_id: "my-client-id")
      }.to raise_error(ChatSDK::ConfigurationError, /access_token or client_id \+ refresh_token/)
    end

    it "falls back to environment variables" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("X_ACCESS_TOKEN").and_return("env-token")
      allow(ENV).to receive(:[]).with("X_CONSUMER_SECRET").and_return("env-secret")
      allow(ENV).to receive(:[]).with("X_USER_ID").and_return("env-user-id")
      allow(ENV).to receive(:[]).with("X_CLIENT_ID").and_return(nil)
      allow(ENV).to receive(:[]).with("X_CLIENT_SECRET").and_return(nil)
      allow(ENV).to receive(:[]).with("X_REFRESH_TOKEN").and_return(nil)

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

    context "favorite events (reactions)" do
      it "parses favorite_events into Reaction event" do
        payload = {
          "favorite_events" => [
            {
              "user" => {"id_str" => "user-111"},
              "favorited_status" => {"id_str" => "tweet-222"}
            }
          ]
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Reaction)
        expect(event.emoji).to eq("heart")
        expect(event.user_id).to eq("user-111")
        expect(event.message_id).to eq("tweet-222")
        expect(event.thread_id).to eq("x:post:tweet-222")
        expect(event.added?).to be true
        expect(event.platform).to eq(:x)
        expect(event.adapter_name).to eq(:x)
      end

      it "skips favorites from the bot itself" do
        payload = {
          "favorite_events" => [
            {
              "user" => {"id_str" => user_id},
              "favorited_status" => {"id_str" => "tweet-333"}
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

  describe "#delete_message" do
    it "deletes a tweet" do
      stub_request(:delete, "https://api.x.com/2/tweets/tweet-123")
        .to_return(
          status: 200,
          body: JSON.generate({"data" => {"deleted" => true}}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.delete_message(channel_id: "ch1", message_id: "tweet-123") }
        .not_to raise_error
    end
  end

  describe "#fetch_messages" do
    context "DM thread" do
      it "fetches DM events for a participant" do
        stub_request(:get, %r{https://api\.x\.com/2/dm_conversations/with/user-789/dm_events\?.*max_results=50})
          .to_return(
            status: 200,
            body: JSON.generate({
              "data" => [
                {"id" => "dm-1", "text" => "Hello", "sender_id" => "user-789"},
                {"id" => "dm-2", "text" => "Hi back", "sender_id" => "user-456"}
              ],
              "meta" => {"next_token" => "cursor-abc"}
            }),
            headers: {"Content-Type" => "application/json"}
          )

        messages, next_cursor = subject.fetch_messages(
          channel_id: "user-789",
          thread_id: "x:dm:user-789"
        )

        expect(messages.size).to eq(2)
        expect(messages.first).to be_a(ChatSDK::Message)
        expect(messages.first.id).to eq("dm-1")
        expect(messages.first.text).to eq("Hello")
        expect(messages.first.author.id).to eq("user-789")
        expect(next_cursor).to eq("cursor-abc")
      end
    end

    context "tweet thread" do
      it "returns empty for tweet threads" do
        messages, next_cursor = subject.fetch_messages(
          channel_id: "user-456",
          thread_id: "x:post:conv-123"
        )

        expect(messages).to eq([])
        expect(next_cursor).to be_nil
      end
    end
  end

  describe "#get_user" do
    it "returns an Author for a valid user" do
      stub_request(:get, "https://api.x.com/2/users/user-123?user.fields=name,username")
        .to_return(
          status: 200,
          body: JSON.generate({"data" => {"id" => "user-123", "name" => "Alice Smith", "username" => "alice"}}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.get_user("user-123")
      expect(result).to be_a(ChatSDK::Author)
      expect(result.id).to eq("user-123")
      expect(result.name).to eq("alice")
      expect(result.platform).to eq(:x)
      expect(result.bot?).to be false
    end
  end

  describe "#open_dm" do
    it "returns the user_id directly" do
      expect(subject.open_dm("user-789")).to eq("user-789")
    end
  end

  describe "#upload_file" do
    it "uploads media and creates a tweet with the media attached" do
      # INIT
      stub_request(:post, "https://api.x.com/2/media/upload")
        .with { |req|
          parsed = JSON.parse(req.body)
          parsed["command"] == "INIT"
        }
        .to_return(
          status: 200,
          body: JSON.generate({"data" => {"id" => "media-123"}}),
          headers: {"Content-Type" => "application/json"}
        )

      # APPEND (multipart)
      stub_request(:post, "https://api.x.com/2/media/upload")
        .with { |req| req.body.to_s.include?("APPEND") }
        .to_return(
          status: 200,
          body: JSON.generate({}),
          headers: {"Content-Type" => "application/json"}
        )

      # FINALIZE
      stub_request(:post, "https://api.x.com/2/media/upload")
        .with { |req|
          next false unless req.body.is_a?(String)

          parsed = begin
            JSON.parse(req.body)
          rescue JSON::ParserError
            nil
          end
          parsed&.dig("command") == "FINALIZE"
        }
        .to_return(
          status: 200,
          body: JSON.generate({"data" => {"id" => "media-123"}}),
          headers: {"Content-Type" => "application/json"}
        )

      # create_tweet with media_ids
      stub_request(:post, "https://api.x.com/2/tweets")
        .with { |req|
          parsed = JSON.parse(req.body)
          parsed["media"] && parsed["media"]["media_ids"] == ["media-123"]
        }
        .to_return(
          status: 200,
          body: JSON.generate({"data" => {"id" => "tweet-media-1", "text" => "Check this out"}}),
          headers: {"Content-Type" => "application/json"}
        )

      io = StringIO.new("fake image data")
      result = subject.upload_file(channel_id: "user-456", io: io, filename: "photo.jpg", comment: "Check this out")

      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("tweet-media-1")
      expect(result.platform).to eq(:x)
    end

    it "uses empty text when no comment is provided" do
      stub_request(:post, "https://api.x.com/2/media/upload").to_return(
        status: 200,
        body: JSON.generate({"data" => {"id" => "media-456"}}),
        headers: {"Content-Type" => "application/json"}
      )

      stub_request(:post, "https://api.x.com/2/tweets")
        .with { |req|
          parsed = JSON.parse(req.body)
          parsed["text"] == ""
        }
        .to_return(
          status: 200,
          body: JSON.generate({"data" => {"id" => "tweet-media-2", "text" => ""}}),
          headers: {"Content-Type" => "application/json"}
        )

      io = StringIO.new("fake image data")
      result = subject.upload_file(channel_id: "user-456", io: io, filename: "photo.png")

      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("tweet-media-2")
    end
  end

  describe "capability gaps" do
    it "raises NotSupportedError for edit_message" do
      expect { subject.edit_message(channel_id: "C1", message_id: "M1", message: "test") }
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

    it "supports delete_messages capability" do
      expect(subject.supports?(:delete_messages)).to be true
    end

    it "supports message_history capability" do
      expect(subject.supports?(:message_history)).to be true
    end

    it "supports file_uploads capability" do
      expect(subject.supports?(:file_uploads)).to be true
    end
  end

  describe "OAuth2 token refresh" do
    let(:client_id) { "test-client-id" }
    let(:client_secret) { "test-client-secret" }
    let(:refresh_token) { "initial-refresh-token" }
    let(:state) { ChatSDK::State::Memory.new }

    let(:oauth_adapter) do
      described_class.new(
        consumer_secret: consumer_secret,
        user_id: user_id,
        client_id: client_id,
        client_secret: client_secret,
        refresh_token: refresh_token
      )
    end

    let(:token_response) do
      {
        "access_token" => "new-access-token",
        "refresh_token" => "rotated-refresh-token",
        "expires_in" => 7200,
        "token_type" => "bearer"
      }
    end

    def stub_token_refresh(response_body: token_response, status: 200)
      stub_request(:post, "https://api.x.com/2/oauth2/token")
        .to_return(
          status: status,
          body: JSON.generate(response_body),
          headers: {"Content-Type" => "application/json"}
        )
    end

    describe "static token mode" do
      it "does not attempt token refresh" do
        stub_request(:post, "https://api.x.com/2/tweets")
          .to_return(
            status: 200,
            body: JSON.generate({"data" => {"id" => "tweet-static-1"}}),
            headers: {"Content-Type" => "application/json"}
          )

        result = subject.post_message(channel_id: "user-456", message: "Static token works")
        expect(result).to be_a(ChatSDK::Message)
        expect(result.id).to eq("tweet-static-1")

        # No call to token endpoint
        expect(WebMock).not_to have_requested(:post, "https://api.x.com/2/oauth2/token")
      end
    end

    describe "managed OAuth mode" do
      it "refreshes token when expired and uses new token for requests" do
        token_stub = stub_token_refresh

        stub_request(:post, "https://api.x.com/2/tweets")
          .to_return(
            status: 200,
            body: JSON.generate({"data" => {"id" => "tweet-oauth-1"}}),
            headers: {"Content-Type" => "application/json"}
          )

        result = oauth_adapter.post_message(channel_id: "user-456", message: "OAuth works")
        expect(result).to be_a(ChatSDK::Message)
        expect(result.id).to eq("tweet-oauth-1")

        # Token was refreshed
        expect(token_stub).to have_been_requested.once
      end

      it "does not refresh when token is still valid" do
        token_stub = stub_token_refresh

        stub_request(:post, "https://api.x.com/2/tweets")
          .to_return(
            status: 200,
            body: JSON.generate({"data" => {"id" => "tweet-1"}}),
            headers: {"Content-Type" => "application/json"}
          )

        # First request triggers refresh
        oauth_adapter.post_message(channel_id: "user-456", message: "First")
        # Second request should reuse the token (not expired yet)
        oauth_adapter.post_message(channel_id: "user-456", message: "Second")

        expect(token_stub).to have_been_requested.once
      end

      it "stores rotated refresh_token" do
        stub_token_refresh
        stub_request(:post, "https://api.x.com/2/tweets")
          .to_return(
            status: 200,
            body: JSON.generate({"data" => {"id" => "tweet-1"}}),
            headers: {"Content-Type" => "application/json"}
          )

        oauth_adapter.set_state(state)
        oauth_adapter.post_message(channel_id: "user-456", message: "Rotate test")

        stored = state.get("x:oauth:#{client_id}")
        expect(stored).to be_a(Hash)
        expect(stored["access_token"]).to eq("new-access-token")
        expect(stored["refresh_token"]).to eq("rotated-refresh-token")
        expect(stored["expires_at"]).to be_a(Float)
      end
    end

    describe "state persistence" do
      it "persists token data to state store via state.set" do
        stub_token_refresh
        stub_request(:post, "https://api.x.com/2/tweets")
          .to_return(
            status: 200,
            body: JSON.generate({"data" => {"id" => "tweet-1"}}),
            headers: {"Content-Type" => "application/json"}
          )

        oauth_adapter.set_state(state)
        oauth_adapter.post_message(channel_id: "user-456", message: "Persist test")

        stored = state.get("x:oauth:#{client_id}")
        expect(stored).not_to be_nil
        expect(stored["access_token"]).to eq("new-access-token")
        expect(stored["refresh_token"]).to eq("rotated-refresh-token")
      end

      it "loads stored token on set_state (survives restarts)" do
        # Pre-populate state with a valid token
        future_time = Time.now + 3600
        state.set("x:oauth:#{client_id}", {
          "access_token" => "stored-access-token",
          "refresh_token" => "stored-refresh-token",
          "expires_at" => future_time.to_f
        })

        stub_request(:post, "https://api.x.com/2/tweets")
          .to_return(
            status: 200,
            body: JSON.generate({"data" => {"id" => "tweet-stored-1"}}),
            headers: {"Content-Type" => "application/json"}
          )

        oauth_adapter.set_state(state)
        result = oauth_adapter.post_message(channel_id: "user-456", message: "Stored token test")
        expect(result.id).to eq("tweet-stored-1")

        # Should NOT have refreshed — stored token is still valid
        expect(WebMock).not_to have_requested(:post, "https://api.x.com/2/oauth2/token")
      end

      it "does not persist when no state store is configured" do
        stub_token_refresh
        stub_request(:post, "https://api.x.com/2/tweets")
          .to_return(
            status: 200,
            body: JSON.generate({"data" => {"id" => "tweet-1"}}),
            headers: {"Content-Type" => "application/json"}
          )

        # No set_state call — adapter has no state store
        oauth_adapter.post_message(channel_id: "user-456", message: "No state")

        # Verify the token was still refreshed (no error), just not persisted
        expect(WebMock).to have_requested(:post, "https://api.x.com/2/oauth2/token").once
      end
    end

    describe "public client (no client_secret)" do
      let(:public_oauth_adapter) do
        described_class.new(
          consumer_secret: consumer_secret,
          user_id: user_id,
          client_id: client_id,
          refresh_token: refresh_token
        )
      end

      it "sends client_id in body and no Basic auth header" do
        token_stub = stub_request(:post, "https://api.x.com/2/oauth2/token")
          .with { |req|
            body_params = URI.decode_www_form(req.body).to_h
            body_params["client_id"] == client_id &&
              body_params["grant_type"] == "refresh_token" &&
              !req.headers.key?("Authorization")
          }
          .to_return(
            status: 200,
            body: JSON.generate(token_response),
            headers: {"Content-Type" => "application/json"}
          )

        stub_request(:post, "https://api.x.com/2/tweets")
          .to_return(
            status: 200,
            body: JSON.generate({"data" => {"id" => "tweet-public-1"}}),
            headers: {"Content-Type" => "application/json"}
          )

        public_oauth_adapter.post_message(channel_id: "user-456", message: "Public client test")
        expect(token_stub).to have_been_requested.once
      end
    end

    describe "confidential client (with client_secret)" do
      it "sends Basic auth header with encoded client_id:client_secret" do
        expected_basic = Base64.strict_encode64("#{client_id}:#{client_secret}")

        token_stub = stub_request(:post, "https://api.x.com/2/oauth2/token")
          .with { |req|
            body_params = URI.decode_www_form(req.body).to_h
            req.headers["Authorization"] == "Basic #{expected_basic}" &&
              !body_params.key?("client_id")
          }
          .to_return(
            status: 200,
            body: JSON.generate(token_response),
            headers: {"Content-Type" => "application/json"}
          )

        stub_request(:post, "https://api.x.com/2/tweets")
          .to_return(
            status: 200,
            body: JSON.generate({"data" => {"id" => "tweet-conf-1"}}),
            headers: {"Content-Type" => "application/json"}
          )

        oauth_adapter.post_message(channel_id: "user-456", message: "Confidential client test")
        expect(token_stub).to have_been_requested.once
      end
    end

    describe "refresh failure" do
      it "raises PlatformError when token refresh fails" do
        stub_request(:post, "https://api.x.com/2/oauth2/token")
          .to_return(
            status: 400,
            body: JSON.generate({"error" => "invalid_grant", "error_description" => "Token has been revoked"}),
            headers: {"Content-Type" => "application/json"}
          )

        expect {
          oauth_adapter.post_message(channel_id: "user-456", message: "Should fail")
        }.to raise_error(ChatSDK::PlatformError, /X token refresh failed.*Token has been revoked/)
      end

      it "raises PlatformError with status for non-JSON error responses" do
        stub_request(:post, "https://api.x.com/2/oauth2/token")
          .to_return(
            status: 500,
            body: "Internal Server Error",
            headers: {"Content-Type" => "text/plain"}
          )

        expect {
          oauth_adapter.post_message(channel_id: "user-456", message: "Should fail")
        }.to raise_error(ChatSDK::PlatformError, /X token refresh failed.*500/)
      end
    end

    describe "#set_state" do
      it "injects state into the adapter and client" do
        oauth_adapter.set_state(state)
        # Verify state was wired by checking persistence works after a refresh
        stub_token_refresh
        stub_request(:post, "https://api.x.com/2/tweets")
          .to_return(
            status: 200,
            body: JSON.generate({"data" => {"id" => "tweet-1"}}),
            headers: {"Content-Type" => "application/json"}
          )

        oauth_adapter.post_message(channel_id: "user-456", message: "State wired")
        expect(state.get("x:oauth:#{client_id}")).not_to be_nil
      end
    end
  end
end
