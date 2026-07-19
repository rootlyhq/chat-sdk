# frozen_string_literal: true

module ChatSDK
  module Telegram
    class EventParser
      class << self
        def parse(payload, bot_username: nil)
          return [] unless payload.is_a?(Hash)

          if payload["callback_query"]
            parse_callback_query(payload["callback_query"])
          elsif payload["message"]
            parse_message(payload["message"], bot_username: bot_username)
          else
            []
          end
        end

        private

        def parse_message(message, bot_username: nil)
          return parse_bot_command(message, extract_user(message), message.dig("chat", "id")&.to_s, resolve_thread_id(message)) if bot_command?(message)

          user = extract_user(message)
          chat_id = message.dig("chat", "id")&.to_s
          chat_type = message.dig("chat", "type")
          text = message["text"] || ""
          thread_id = resolve_thread_id(message)

          msg = ChatSDK::Message.new(
            id: message["message_id"]&.to_s,
            text: text,
            author: ChatSDK::Author.new(id: user[:id], name: user[:name], platform: :telegram, bot: false, locale: user[:locale]),
            thread_id: thread_id,
            channel_id: chat_id,
            platform: :telegram,
            raw: message
          )

          event_class = if mention?(text, bot_username)
            ChatSDK::Events::Mention
          elsif chat_type == "private"
            ChatSDK::Events::DirectMessage
          else
            ChatSDK::Events::SubscribedMessage
          end

          [event_class.new(message: msg, thread_id: thread_id, channel_id: chat_id,
            platform: :telegram, adapter_name: :telegram, raw: message)]
        end

        def parse_callback_query(callback)
          user_info = callback["from"] || {}
          message = callback["message"] || {}
          chat_id = message.dig("chat", "id")&.to_s
          message_id = message["message_id"]&.to_s
          callback_data = callback["data"] || ""

          action_id, value = callback_data.split(":", 2)
          value ||= action_id

          user = ChatSDK::Author.new(
            id: user_info["id"]&.to_s || "unknown",
            name: user_info["username"] || user_info["first_name"] || "unknown",
            platform: :telegram,
            bot: false,
            locale: user_info["language_code"]
          )

          [ChatSDK::Events::Action.new(
            action_id: action_id,
            value: value,
            user: user,
            thread_id: message_id,
            channel_id: chat_id,
            platform: :telegram,
            adapter_name: :telegram,
            raw: callback
          )]
        end

        def extract_user(message)
          from = message["from"] || {}
          {
            id: from["id"]&.to_s || "unknown",
            name: from["username"] || from["first_name"] || "unknown",
            locale: from["language_code"]
          }
        end

        def resolve_thread_id(message)
          reply = message.dig("reply_to_message", "message_id")
          (reply || message["message_id"])&.to_s
        end

        def bot_command?(message)
          entities = message["entities"]
          return false unless entities.is_a?(Array)

          entities.any? { |e| e["type"] == "bot_command" }
        end

        def mention?(text, bot_username)
          return false unless bot_username

          text.include?("@#{bot_username}")
        end

        def parse_bot_command(message, user, chat_id, thread_id)
          text = message["text"] || ""
          parts = text.split(" ", 2)
          command = parts[0]&.split("@")&.first || ""
          args = parts[1] || ""

          [ChatSDK::Events::SlashCommand.new(
            command: command,
            text: args,
            user_id: user[:id],
            channel_id: chat_id,
            trigger_id: message["message_id"]&.to_s,
            platform: :telegram,
            adapter_name: :telegram,
            raw: message
          )]
        end
      end
    end
  end
end
