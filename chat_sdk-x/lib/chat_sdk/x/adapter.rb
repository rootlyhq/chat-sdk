# frozen_string_literal: true

require "openssl"
require "base64"
require "rack/utils"

module ChatSDK
  module X
    class Adapter < ChatSDK::Adapter::Base
      capabilities :direct_messages, :reactions, :delete_messages, :message_history

      attr_reader :client

      def initialize(access_token: nil, consumer_secret: nil, user_id: nil)
        @access_token = access_token || ENV["X_ACCESS_TOKEN"]
        @consumer_secret = consumer_secret || ENV["X_CONSUMER_SECRET"]
        @user_id = user_id || ENV["X_USER_ID"]

        raise ChatSDK::ConfigurationError, "X access_token required" unless @access_token
        raise ChatSDK::ConfigurationError, "X consumer_secret required" unless @consumer_secret

        @client = ApiClient.new(@access_token)
      end

      def name
        :x
      end

      # Inbound
      def verify_request!(rack_request)
        body = rack_request.body.read
        rack_request.body.rewind

        signature = rack_request.get_header("HTTP_X_TWITTER_WEBHOOKS_SIGNATURE")

        unless signature
          raise ChatSDK::SignatureVerificationError, "Missing X signature header"
        end

        expected = "sha256=#{Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", @consumer_secret, body))}"

        unless Rack::Utils.secure_compare(signature, expected)
          raise ChatSDK::SignatureVerificationError, "Invalid X signature"
        end

        true
      end

      def ack_response(rack_request)
        return nil unless rack_request.get?

        crc_token = rack_request.params["crc_token"]
        return nil unless crc_token

        response_token = "sha256=#{Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", @consumer_secret, crc_token))}"

        [200, {"content-type" => "application/json"}, [JSON.generate({"response_token" => response_token})]]
      end

      def parse_events(rack_request)
        payload = read_json_body(rack_request)
        EventParser.parse(payload, bot_user_id: @user_id)
      rescue JSON::ParserError
        []
      end

      # Outbound
      def post_message(channel_id:, message:, thread_id: nil)
        msg = ChatSDK::PostableMessage.from(message)
        text = msg.text || msg.card&.fallback_text || ""

        if thread_id&.start_with?("x:dm:")
          result = @client.send_dm(participant_id: channel_id, text: text)
          message_id = result.dig("dm_event", "id") || result["id"]

          ChatSDK::Message.new(
            id: message_id,
            text: text,
            author: ChatSDK::Author.new(id: @user_id || "bot", name: "bot", platform: :x, bot: true),
            thread_id: thread_id,
            channel_id: channel_id,
            platform: :x,
            raw: result
          )
        else
          payload = {text: text}
          payload[:reply] = {in_reply_to_tweet_id: channel_id} if channel_id && thread_id
          result = @client.create_tweet(**payload)
          tweet_id = result.dig("data", "id") || result["id"]

          ChatSDK::Message.new(
            id: tweet_id,
            text: text,
            author: ChatSDK::Author.new(id: @user_id || "bot", name: "bot", platform: :x, bot: true),
            thread_id: thread_id || "x:post:#{tweet_id}",
            channel_id: channel_id,
            platform: :x,
            raw: result
          )
        end
      end

      def delete_message(channel_id:, message_id:) # rubocop:disable Lint/UnusedMethodArgument
        @client.delete_tweet(tweet_id: message_id)
      end

      def fetch_messages(channel_id:, thread_id: nil, cursor: nil, limit: 50) # rubocop:disable Lint/UnusedMethodArgument
        if thread_id&.start_with?("x:dm:")
          participant_id = thread_id.delete_prefix("x:dm:")
          result = @client.get_dm_events(participant_id: participant_id, cursor: cursor, limit: limit)
          data = result["data"] || []
          messages = data.map do |dm|
            ChatSDK::Message.new(
              id: dm["id"]&.to_s,
              text: dm["text"] || "",
              author: ChatSDK::Author.new(
                id: dm["sender_id"] || "unknown",
                name: dm["sender_id"] || "unknown",
                platform: :x,
                bot: false
              ),
              thread_id: thread_id,
              channel_id: channel_id,
              platform: :x,
              raw: dm
            )
          end
          next_cursor = result.dig("meta", "next_token")
          [messages, next_cursor]
        else
          # X does not provide a robust thread-fetching API for tweets
          [[], nil]
        end
      end

      def add_reaction(channel_id:, message_id:, emoji:) # rubocop:disable Lint/UnusedMethodArgument
        @client.like_tweet(user_id: @user_id, tweet_id: message_id)
      end

      def remove_reaction(channel_id:, message_id:, emoji:) # rubocop:disable Lint/UnusedMethodArgument
        @client.unlike_tweet(user_id: @user_id, tweet_id: message_id)
      end

      def open_dm(user_id)
        user_id
      end

      def mention(user_id)
        "@#{user_id}"
      end

      def render(postable_message)
        postable_message.text
      end
    end
  end
end
