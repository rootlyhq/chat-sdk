# frozen_string_literal: true

module ChatSDK
  module Mattermost
    class Adapter < ChatSDK::Adapter::Base
      capabilities :edit_messages, :delete_messages, :ephemeral_messages, :reactions,
        :typing_indicator, :streaming_edit, :threads, :direct_messages,
        :message_history, :file_uploads

      attr_reader :client

      def initialize(base_url: nil, bot_token: nil, webhook_token: nil, bot_user_id: nil)
        @base_url = base_url || ENV["MATTERMOST_BASE_URL"]
        @bot_token = bot_token || ENV["MATTERMOST_BOT_TOKEN"]
        @webhook_token = webhook_token || ENV["MATTERMOST_WEBHOOK_TOKEN"]
        @bot_user_id = bot_user_id || ENV["MATTERMOST_BOT_USER_ID"]

        raise ChatSDK::ConfigurationError, "Mattermost base_url required" unless @base_url
        raise ChatSDK::ConfigurationError, "Mattermost bot_token required" unless @bot_token

        @client = ApiClient.new(base_url: @base_url, bot_token: @bot_token)
        @renderer = AttachmentRenderer.new
      end

      def name
        :mattermost
      end

      # Inbound
      def verify_request!(rack_request)
        body = rack_request.body.read
        rack_request.body.rewind

        payload = begin
          JSON.parse(body)
        rescue JSON::ParserError
          raise ChatSDK::SignatureVerificationError, "Invalid JSON payload"
        end

        return true unless @webhook_token

        token = payload["token"]
        unless token && secure_compare(token, @webhook_token)
          raise ChatSDK::SignatureVerificationError, "Invalid webhook token"
        end

        true
      end

      def parse_events(rack_request)
        body = rack_request.body.read
        rack_request.body.rewind

        payload = JSON.parse(body)
        EventParser.parse(payload, bot_user_id: @bot_user_id)
      rescue JSON::ParserError
        []
      end

      # Outbound
      def post_message(channel_id:, message:, thread_id: nil)
        msg = ChatSDK::PostableMessage.from(message)

        props = nil
        if msg.card?
          attachments = @renderer.render(msg.card)
          props = {"attachments" => attachments}
        end

        result = @client.create_post(
          channel_id: channel_id,
          message: msg.text || msg.card&.fallback_text || "",
          root_id: thread_id,
          props: props
        )

        ChatSDK::Message.new(
          id: result["id"],
          text: msg.text || "",
          author: ChatSDK::Author.new(id: @bot_user_id || "bot", name: "bot", platform: :mattermost, bot: true),
          thread_id: thread_id || result["id"],
          channel_id: channel_id,
          platform: :mattermost,
          raw: result
        )
      end

      def edit_message(channel_id:, message_id:, message:)
        require_capability!(:edit_messages)
        msg = ChatSDK::PostableMessage.from(message)

        props = nil
        if msg.card?
          attachments = @renderer.render(msg.card)
          props = {"attachments" => attachments}
        end

        @client.update_post(
          post_id: message_id,
          message: msg.text || msg.card&.fallback_text || "",
          props: props
        )
      end

      def delete_message(channel_id:, message_id:)
        require_capability!(:delete_messages)
        @client.delete_post(post_id: message_id)
      end

      def post_ephemeral(channel_id:, user_id:, message:, thread_id: nil)
        require_capability!(:ephemeral_messages)
        msg = ChatSDK::PostableMessage.from(message)
        @client.create_ephemeral_post(
          user_id: user_id,
          channel_id: channel_id,
          message: msg.text || msg.card&.fallback_text || ""
        )
      end

      def upload_file(channel_id:, io:, filename:, thread_id: nil, comment: nil)
        require_capability!(:file_uploads)

        file_result = @client.upload_file(channel_id: channel_id, io: io, filename: filename)
        file_ids = file_result.dig("file_infos")&.map { |fi| fi["id"] } || []

        body = {"channel_id" => channel_id, "message" => comment || "", "file_ids" => file_ids}
        body["root_id"] = thread_id if thread_id

        @client.create_post(
          channel_id: channel_id,
          message: comment || "",
          root_id: thread_id,
          props: nil
        )
      end

      def add_reaction(channel_id:, message_id:, emoji:)
        require_capability!(:reactions)
        raise ChatSDK::ConfigurationError, "bot_user_id required for reactions" unless @bot_user_id

        @client.add_reaction(
          user_id: @bot_user_id,
          post_id: message_id,
          emoji_name: emoji
        )
      end

      def remove_reaction(channel_id:, message_id:, emoji:)
        require_capability!(:reactions)
        raise ChatSDK::ConfigurationError, "bot_user_id required for reactions" unless @bot_user_id

        @client.remove_reaction(
          user_id: @bot_user_id,
          post_id: message_id,
          emoji_name: emoji
        )
      end

      def open_dm(user_id)
        require_capability!(:direct_messages)
        raise ChatSDK::ConfigurationError, "bot_user_id required for DMs" unless @bot_user_id

        result = @client.create_direct_channel([@bot_user_id, user_id])
        result["id"]
      end

      def fetch_messages(channel_id:, thread_id: nil, cursor: nil, limit: 50)
        require_capability!(:message_history)

        if thread_id
          result = @client.get_post_thread(post_id: thread_id)
        else
          page = cursor&.to_i || 0
          result = @client.get_channel_posts(channel_id: channel_id, page: page, per_page: limit)
        end

        order = result["order"] || []
        posts = result["posts"] || {}

        messages = order.map do |post_id|
          post = posts[post_id]
          next unless post

          ChatSDK::Message.new(
            id: post["id"],
            text: post["message"] || "",
            author: ChatSDK::Author.new(
              id: post["user_id"] || "unknown",
              name: post["user_id"] || "unknown",
              platform: :mattermost
            ),
            thread_id: post["root_id"].to_s.empty? ? post["id"] : post["root_id"],
            channel_id: post["channel_id"],
            platform: :mattermost,
            raw: post
          )
        end.compact

        next_cursor = thread_id ? nil : ((cursor&.to_i || 0) + 1).to_s
        [messages, next_cursor]
      end

      def open_modal(trigger_id:, modal:)
        super # raises NotSupportedError
      end

      def start_typing(channel_id:, thread_id: nil)
        require_capability!(:typing_indicator)
        @client.send_typing(channel_id: channel_id)
      end

      def mention(user_id)
        "@#{user_id}"
      end

      def render(postable_message)
        msg = ChatSDK::PostableMessage.from(postable_message)
        if msg.card?
          @renderer.render(msg.card)
        else
          msg.text
        end
      end

      private

      def secure_compare(a, b)
        return false unless a.bytesize == b.bytesize

        l = a.unpack("C*")
        r = b.unpack("C*")
        result = 0
        l.zip(r) { |x, y| result |= x ^ y }
        result.zero?
      end
    end
  end
end
