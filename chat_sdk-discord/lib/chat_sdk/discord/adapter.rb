# frozen_string_literal: true

require "erb"

module ChatSDK
  module Discord
    class Adapter < ChatSDK::Adapter::Base
      capabilities :edit_messages, :delete_messages, :reactions, :file_uploads,
        :threads, :direct_messages, :message_history, :streaming_edit

      attr_reader :client

      def initialize(bot_token: nil, public_key: nil, application_id: nil)
        @bot_token = bot_token || ENV["DISCORD_BOT_TOKEN"]
        @public_key = public_key || ENV["DISCORD_PUBLIC_KEY"]
        @application_id = application_id || ENV["DISCORD_APPLICATION_ID"]

        raise ChatSDK::ConfigurationError, "Discord bot_token required" unless @bot_token

        @client = ApiClient.new(bot_token: @bot_token)
        @renderer = EmbedRenderer.new
      end

      def name
        :discord
      end

      # Inbound
      def verify_request!(rack_request)
        body = rack_request.body.read
        rack_request.body.rewind

        unless @public_key
          raise ChatSDK::ConfigurationError, "Discord public_key required for signature verification"
        end

        signature = rack_request.get_header("HTTP_X_SIGNATURE_ED25519")
        timestamp = rack_request.get_header("HTTP_X_SIGNATURE_TIMESTAMP")

        unless signature && timestamp
          raise ChatSDK::SignatureVerificationError, "Missing Discord signature headers"
        end

        Signature.verify!(@public_key, signature, timestamp, body)
      end

      def ack_response(rack_request)
        body = rack_request.body.read
        rack_request.body.rewind

        payload = begin
          JSON.parse(body)
        rescue JSON::ParserError
          return nil
        end

        return nil unless payload["type"] == 1

        [200, {"content-type" => "application/json"}, ['{"type":1}']]
      end

      def parse_events(rack_request)
        body = rack_request.body.read
        rack_request.body.rewind

        payload = JSON.parse(body)
        EventParser.parse(payload)
      rescue JSON::ParserError
        []
      end

      # Outbound
      def post_message(channel_id:, message:, thread_id: nil)
        msg = ChatSDK::PostableMessage.from(message)

        content = msg.text || msg.card&.fallback_text || ""
        embeds = nil
        components = nil

        if msg.card?
          rendered = @renderer.render(msg.card)
          embeds = rendered["embeds"]
          components = rendered["components"]
        end

        result = @client.create_message(
          channel_id,
          content: content,
          embeds: embeds,
          components: components
        )

        ChatSDK::Message.new(
          id: result["id"],
          text: content,
          author: ChatSDK::Author.new(id: @application_id || "bot", name: "bot", platform: :discord, bot: true),
          thread_id: thread_id || result["id"],
          channel_id: channel_id,
          platform: :discord,
          raw: result
        )
      end

      def edit_message(channel_id:, message_id:, message:)
        require_capability!(:edit_messages)
        msg = ChatSDK::PostableMessage.from(message)

        content = msg.text || msg.card&.fallback_text || ""
        embeds = nil
        components = nil

        if msg.card?
          rendered = @renderer.render(msg.card)
          embeds = rendered["embeds"]
          components = rendered["components"]
        end

        @client.edit_message(
          channel_id,
          message_id,
          content: content,
          embeds: embeds,
          components: components
        )
      end

      def delete_message(channel_id:, message_id:)
        require_capability!(:delete_messages)
        @client.delete_message(channel_id, message_id)
      end

      def post_ephemeral(channel_id:, user_id:, message:, thread_id: nil)
        super # raises NotSupportedError
      end

      def upload_file(channel_id:, io:, filename:, thread_id: nil, comment: nil)
        require_capability!(:file_uploads)
        @client.upload_file(channel_id, io, filename)
      end

      def add_reaction(channel_id:, message_id:, emoji:)
        require_capability!(:reactions)
        @client.add_reaction(channel_id, message_id, emoji)
      end

      def remove_reaction(channel_id:, message_id:, emoji:)
        require_capability!(:reactions)
        @client.remove_reaction(channel_id, message_id, emoji)
      end

      def open_dm(user_id)
        require_capability!(:direct_messages)
        result = @client.create_dm(user_id)
        result["id"]
      end

      def fetch_messages(channel_id:, thread_id: nil, cursor: nil, limit: 50)
        require_capability!(:message_history)

        messages_data = @client.get_messages(channel_id, limit: limit, before: cursor)
        messages_data = [] unless messages_data.is_a?(Array)

        messages = messages_data.map do |msg|
          ChatSDK::Message.new(
            id: msg["id"],
            text: msg["content"] || "",
            author: ChatSDK::Author.new(
              id: msg.dig("author", "id") || "unknown",
              name: msg.dig("author", "username") || "unknown",
              platform: :discord
            ),
            thread_id: msg["id"],
            channel_id: channel_id,
            platform: :discord,
            raw: msg
          )
        end

        next_cursor = messages_data.any? ? messages_data.last["id"] : nil
        [messages, next_cursor]
      end

      def open_modal(trigger_id:, modal:)
        super # raises NotSupportedError
      end

      def start_typing(channel_id:, thread_id: nil)
        super # raises NotSupportedError
      end

      def mention(user_id)
        "<@#{user_id}>"
      end

      def render(postable_message)
        msg = ChatSDK::PostableMessage.from(postable_message)
        if msg.card?
          @renderer.render(msg.card)
        else
          msg.text
        end
      end
    end
  end
end
