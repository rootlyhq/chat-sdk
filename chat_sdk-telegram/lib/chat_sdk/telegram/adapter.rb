# frozen_string_literal: true

require "rack/utils"

module ChatSDK
  module Telegram
    class Adapter < ChatSDK::Adapter::Base
      capabilities :edit_messages, :delete_messages, :reactions, :file_uploads,
        :typing_indicator, :streaming_edit, :direct_messages

      attr_reader :client

      def initialize(bot_token: nil, secret_token: nil, bot_username: nil)
        @bot_token = bot_token || ENV["TELEGRAM_BOT_TOKEN"]
        @secret_token = secret_token || ENV["TELEGRAM_WEBHOOK_SECRET_TOKEN"]
        @bot_username = bot_username || ENV["TELEGRAM_BOT_USERNAME"]

        raise ChatSDK::ConfigurationError, "Telegram bot_token required" unless @bot_token

        @client = ApiClient.new(@bot_token)
        @renderer = KeyboardRenderer.new
      end

      def name
        :telegram
      end

      # Inbound
      def verify_request!(rack_request)
        return true unless @secret_token

        header_token = rack_request.get_header("HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN")

        unless header_token
          raise ChatSDK::SignatureVerificationError, "Missing Telegram secret token header"
        end

        unless Rack::Utils.secure_compare(header_token, @secret_token)
          raise ChatSDK::SignatureVerificationError, "Invalid Telegram secret token"
        end

        true
      end

      def ack_response(_rack_request)
        nil
      end

      def parse_events(rack_request)
        body = rack_request.body.read
        rack_request.body.rewind

        payload = JSON.parse(body)
        EventParser.parse(payload, bot_username: @bot_username)
      rescue JSON::ParserError
        []
      end

      # Outbound
      def post_message(channel_id:, message:, thread_id: nil)
        text, reply_markup = prepare_message_payload(message)

        result = @client.send_message(
          chat_id: channel_id,
          text: text,
          reply_markup: reply_markup,
          reply_to_message_id: thread_id
        )

        parse_telegram_message(result, channel_id)
      end

      def edit_message(channel_id:, message_id:, message:)
        text, reply_markup = prepare_message_payload(message)

        @client.edit_message_text(
          chat_id: channel_id,
          message_id: message_id,
          text: text,
          reply_markup: reply_markup
        )
      end

      def delete_message(channel_id:, message_id:)
        @client.delete_message(chat_id: channel_id, message_id: message_id)
      end

      def upload_file(channel_id:, io:, filename:, thread_id: nil, comment: nil)
        @client.send_document(
          chat_id: channel_id,
          document: io,
          filename: filename,
          caption: comment,
          reply_to_message_id: thread_id
        )
      end

      def add_reaction(channel_id:, message_id:, emoji:)
        @client.set_message_reaction(
          chat_id: channel_id,
          message_id: message_id,
          reaction: [{"type" => "emoji", "emoji" => emoji}]
        )
      end

      def remove_reaction(channel_id:, message_id:, emoji:) # rubocop:disable Lint/UnusedMethodArgument
        @client.set_message_reaction(
          chat_id: channel_id,
          message_id: message_id,
          reaction: []
        )
      end

      def open_dm(user_id)
        user_id
      end

      def start_typing(channel_id:, thread_id: nil) # rubocop:disable Lint/UnusedMethodArgument
        @client.send_chat_action(chat_id: channel_id, action: "typing")
      end

      def mention(user_id)
        "[user](tg://user?id=#{user_id})"
      end

      def render(postable_message)
        if postable_message.card?
          @renderer.render(postable_message.card)
        else
          postable_message.text
        end
      end

      private

      def prepare_message_payload(message)
        msg = ChatSDK::PostableMessage.from(message)
        text = msg.text || msg.card&.fallback_text || ""
        reply_markup = nil
        if msg.card?
          rendered = @renderer.render(msg.card)
          text = rendered[:text] if rendered[:text] && !rendered[:text].empty?
          reply_markup = rendered[:reply_markup]
        end
        [text, reply_markup]
      end

      def parse_telegram_message(data, channel_id)
        ChatSDK::Message.new(
          id: data["message_id"]&.to_s,
          text: data["text"] || "",
          author: ChatSDK::Author.new(
            id: data.dig("from", "id")&.to_s || "bot",
            name: data.dig("from", "username") || "bot",
            platform: :telegram,
            bot: true
          ),
          thread_id: data["message_id"]&.to_s,
          channel_id: channel_id,
          platform: :telegram,
          raw: data
        )
      end
    end
  end
end
