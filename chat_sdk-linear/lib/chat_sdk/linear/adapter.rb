# frozen_string_literal: true

require "openssl"
require "rack/utils"

module ChatSDK
  module Linear
    class Adapter < ChatSDK::Adapter::Base
      capabilities

      attr_reader :client

      def initialize(api_key: nil, webhook_secret: nil, bot_username: nil)
        @api_key = api_key || ENV["LINEAR_API_KEY"]
        @webhook_secret = webhook_secret || ENV["LINEAR_WEBHOOK_SECRET"]
        @bot_username = bot_username || ENV["LINEAR_BOT_USERNAME"]
        raise ChatSDK::ConfigurationError, "Linear api_key required" unless @api_key
        raise ChatSDK::ConfigurationError, "Linear webhook_secret required" unless @webhook_secret

        @client = ApiClient.new(@api_key)
      end

      def name
        :linear
      end

      # Inbound
      def verify_request!(rack_request)
        body = rack_request.body.read
        rack_request.body.rewind

        signature = rack_request.get_header("HTTP_LINEAR_SIGNATURE")

        unless signature
          raise ChatSDK::SignatureVerificationError, "Missing Linear signature header"
        end

        expected = OpenSSL::HMAC.hexdigest("SHA256", @webhook_secret, body)

        unless Rack::Utils.secure_compare(signature, expected)
          raise ChatSDK::SignatureVerificationError, "Invalid Linear signature"
        end

        true
      end

      def ack_response(_rack_request)
        nil
      end

      def parse_events(rack_request)
        payload = read_json_body(rack_request)
        EventParser.parse(payload, bot_username: @bot_username)
      rescue JSON::ParserError
        []
      end

      # Outbound
      def post_message(channel_id:, message:, thread_id: nil)
        msg = ChatSDK::PostableMessage.from(message)
        text = msg.text || msg.card&.fallback_text || ""

        issue_id = channel_id
        parent_id = nil

        if thread_id&.include?(":c:")
          parts = thread_id.split(":c:")
          parent_id = parts.last
        end

        result = @client.create_comment(issue_id: issue_id, body: text, parent_id: parent_id)
        comment = result.dig("data", "commentCreate", "comment") || {}
        comment_id = comment["id"]
        user = comment["user"] || {}

        ChatSDK::Message.new(
          id: comment_id,
          text: text,
          author: ChatSDK::Author.new(
            id: user["id"] || "bot",
            name: user["name"] || "bot",
            platform: :linear,
            bot: true
          ),
          thread_id: "linear:#{issue_id}:c:#{comment_id}",
          channel_id: channel_id,
          platform: :linear,
          raw: result
        )
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
