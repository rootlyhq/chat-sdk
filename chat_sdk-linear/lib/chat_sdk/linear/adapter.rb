# frozen_string_literal: true

require "openssl"
require "rack/utils"

module ChatSDK
  module Linear
    class Adapter < ChatSDK::Adapter::Base
      capabilities :threads, :edit_messages, :delete_messages, :reactions, :message_history, :streaming_edit

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

      def edit_message(channel_id:, message_id:, message:, thread_id: nil)
        validate_comment_ownership!(channel_id, message_id, thread_id)
        msg = ChatSDK::PostableMessage.from(message)
        text = msg.text || msg.card&.fallback_text || ""
        @client.update_comment(comment_id: message_id, body: text)
      end

      def delete_message(channel_id:, message_id:, thread_id: nil)
        validate_comment_ownership!(channel_id, message_id, thread_id)
        @client.delete_comment(comment_id: message_id)
      end

      def add_reaction(channel_id:, message_id:, emoji:, thread_id: nil)
        validate_comment_ownership!(channel_id, message_id, thread_id)
        @client.create_reaction(comment_id: message_id, emoji: emoji)
      end

      def remove_reaction(channel_id:, message_id:, emoji:, thread_id: nil)
        validate_comment_ownership!(channel_id, message_id, thread_id)
        @client.delete_reaction(comment_id: message_id, emoji: emoji)
      end

      def fetch_messages(channel_id:, thread_id: nil, limit: 50) # rubocop:disable Lint/UnusedMethodArgument
        issue_id = channel_id
        parent_id = nil

        if thread_id&.include?(":c:")
          parent_id = thread_id.split(":c:", 2).last
          validate_comment_ownership!(issue_id, parent_id, nil)
        end

        result = @client.fetch_comments(issue_id: issue_id, parent_id: parent_id)
        comments = if parent_id
          result.dig("data", "comment", "children", "nodes") || []
        else
          result.dig("data", "comments", "nodes") || []
        end

        messages = comments.map do |comment|
          user = comment["user"] || {}
          ChatSDK::Message.new(
            id: comment["id"],
            text: comment["body"] || "",
            author: ChatSDK::Author.new(id: user["id"] || "unknown", name: user["name"] || "unknown", platform: :linear, bot: false),
            thread_id: "linear:#{issue_id}:c:#{comment["id"]}",
            channel_id: channel_id,
            platform: :linear,
            raw: comment
          )
        end

        [messages, nil]
      end

      def mention(user_id)
        "@#{user_id}"
      end

      def render(postable_message)
        postable_message.text
      end

      private

      def validate_comment_ownership!(channel_id, message_id, thread_id)
        comment = @client.fetch_comment(comment_id: message_id)
        issue_id = comment&.dig("issue", "id")
        unless comment && same_identifier?(issue_id, channel_id)
          raise ChatSDK::Error, "Linear comment does not belong to issue #{channel_id}"
        end

        root_id = thread_root_id(thread_id)
        return unless root_id
        return if same_identifier?(comment["id"], root_id)

        root = @client.fetch_comment(comment_id: root_id)
        root_issue_id = root&.dig("issue", "id")
        unless root && same_identifier?(root_issue_id, channel_id) &&
            same_identifier?(comment.dig("parent", "id"), root_id)
          raise ChatSDK::Error, "Linear comment does not belong to thread #{thread_id}"
        end
      end

      def thread_root_id(thread_id)
        return unless thread_id.is_a?(String) && thread_id.include?(":c:")

        thread_id.split(":c:", 2).last
      end

      def same_identifier?(left, right)
        left.is_a?(String) && right.is_a?(String) && left.casecmp?(right)
      end
    end
  end
end
