# frozen_string_literal: true

module ChatSDK
  module Discord
    class Adapter < ChatSDK::Adapter::Base
      capabilities :edit_messages, :delete_messages, :reactions, :file_uploads,
        :threads, :direct_messages, :message_history, :streaming_edit,
        :typing_indicator

      attr_reader :client

      def initialize(bot_token: nil, public_key: nil, application_id: nil)
        @bot_token = bot_token || ENV["DISCORD_BOT_TOKEN"]
        @public_key = public_key || ENV["DISCORD_PUBLIC_KEY"]
        @application_id = application_id || ENV["DISCORD_APPLICATION_ID"]

        raise ChatSDK::ConfigurationError, "Discord bot_token required" unless @bot_token

        @client = ApiClient.new(bot_token: @bot_token)
        @renderer = EmbedRenderer.new
        @verify_key = Ed25519::VerifyKey.new([@public_key].pack("H*")) if @public_key
        @dm_channels = {}
      end

      def name
        :discord
      end

      # Inbound
      def verify_request!(rack_request)
        body = rack_request.body.read
        rack_request.body.rewind

        unless @verify_key
          raise ChatSDK::ConfigurationError, "Discord public_key required for signature verification"
        end

        signature = rack_request.get_header("HTTP_X_SIGNATURE_ED25519")
        timestamp = rack_request.get_header("HTTP_X_SIGNATURE_TIMESTAMP")

        unless signature && timestamp
          raise ChatSDK::SignatureVerificationError, "Missing Discord signature headers"
        end

        Signature.verify!(@verify_key, signature, timestamp, body)
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
        payload = read_json_body(rack_request)
        EventParser.parse(payload)
      rescue JSON::ParserError
        []
      end

      # Outbound
      def post_message(channel_id:, message:, thread_id: nil)
        content, embeds, components = prepare_message_payload(message)

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
        content, embeds, components = prepare_message_payload(message)

        @client.edit_message(
          channel_id,
          message_id,
          content: content,
          embeds: embeds,
          components: components
        )
      end

      def delete_message(channel_id:, message_id:)
        @client.delete_message(channel_id, message_id)
      end

      def upload_file(channel_id:, io:, filename:, thread_id: nil, comment: nil)
        @client.upload_file(channel_id, io, filename)
      end

      def add_reaction(channel_id:, message_id:, emoji:)
        @client.add_reaction(channel_id, message_id, emoji)
      end

      def remove_reaction(channel_id:, message_id:, emoji:)
        @client.remove_reaction(channel_id, message_id, emoji)
      end

      def get_user(user_id)
        data = @client.get_user(user_id)
        return nil unless data && data["id"]

        ChatSDK::Author.new(
          id: data["id"],
          name: data["username"],
          platform: :discord,
          bot: data["bot"] || false,
          raw: data
        )
      end

      def open_dm(user_id)
        @dm_channels[user_id] ||= @client.create_dm(user_id)["id"]
      end

      def fetch_messages(channel_id:, thread_id: nil, cursor: nil, limit: 50)
        messages_data = @client.get_messages(channel_id, limit: limit, before: cursor)
        messages_data = [] unless messages_data.is_a?(Array)

        messages = messages_data.map do |data|
          parse_discord_message(data, channel_id)
        end

        next_cursor = messages_data.any? ? messages_data.last["id"] : nil
        [messages, next_cursor]
      end

      def start_typing(channel_id:, thread_id: nil)
        @client.trigger_typing(channel_id)
      end

      def mention(user_id)
        "<@#{user_id}>"
      end

      def render(postable_message)
        if postable_message.card?
          @renderer.render(postable_message.card)
        else
          postable_message.text
        end
      end

      # Discord-specific: receive real-time events via the Discord Gateway WebSocket.
      # Requires the optional 'discordrb' gem. Not part of the base adapter contract.
      def start_gateway(&block)
        raise ArgumentError, "start_gateway requires a block" unless block

        begin
          require "discordrb"
        rescue LoadError
          raise ChatSDK::ConfigurationError,
            "Discord gateway requires the 'discordrb' gem. Add gem 'discordrb' to your Gemfile."
        end

        bot = Discordrb::Bot.new(token: "Bot #{@bot_token}")

        bot.message do |event|
          next if event.author.bot_account?

          author = ChatSDK::Author.new(
            id: event.author.id.to_s,
            name: event.author.username,
            platform: :discord,
            bot: false
          )
          message = ChatSDK::Message.new(
            id: event.message.id.to_s,
            text: event.message.content,
            author: author,
            thread_id: event.message.id.to_s,
            channel_id: event.channel.id.to_s,
            platform: :discord,
            raw: {content: event.message.content, author_id: event.author.id.to_s}
          )

          mention_event = ChatSDK::Events::Mention.new(
            message: message,
            thread_id: message.thread_id,
            channel_id: message.channel_id,
            platform: :discord,
            adapter_name: :discord,
            raw: message.raw
          )

          block.call(mention_event)
        end

        bot.run
      end

      private

      def prepare_message_payload(message)
        msg = ChatSDK::PostableMessage.from(message)
        content = msg.text || msg.card&.fallback_text || ""
        embeds = nil
        components = nil
        if msg.card?
          rendered = @renderer.render(msg.card)
          embeds = rendered["embeds"]
          components = rendered["components"]
        end
        [content, embeds, components]
      end

      def parse_discord_message(data, channel_id)
        ChatSDK::Message.new(
          id: data["id"],
          text: data["content"] || "",
          author: ChatSDK::Author.new(
            id: data.dig("author", "id") || "unknown",
            name: data.dig("author", "username") || "unknown",
            platform: :discord
          ),
          thread_id: data["id"],
          channel_id: channel_id,
          platform: :discord,
          raw: data
        )
      end
    end
  end
end
