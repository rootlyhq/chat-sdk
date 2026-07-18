# frozen_string_literal: true

module ChatSDK
  module GChat
    class EventParser
      class << self
        def parse(payload)
          type = payload["type"]

          case type
          when "MESSAGE"
            parse_message(payload)
          when "CARD_CLICKED"
            parse_card_clicked(payload)
          when "ADDED_TO_SPACE", "REMOVED_FROM_SPACE"
            []
          else
            []
          end
        end

        private

        def parse_message(payload)
          msg_data = payload["message"] || {}
          sender = msg_data["sender"] || {}
          space = msg_data["space"] || {}
          thread_data = msg_data["thread"] || {}

          author = ChatSDK::Author.new(
            id: extract_id(sender["name"]),
            name: sender["displayName"] || sender["name"] || "unknown",
            platform: :gchat,
            bot: sender["type"] == "BOT"
          )

          message = ChatSDK::Message.new(
            id: extract_id(msg_data["name"]),
            text: msg_data["text"] || msg_data["argumentText"] || "",
            author: author,
            thread_id: extract_id(thread_data["name"]),
            channel_id: extract_id(space["name"]),
            platform: :gchat,
            raw: msg_data
          )

          if bot_mentioned?(msg_data)
            [ChatSDK::Events::Mention.new(
              message: message,
              thread_id: message.thread_id,
              channel_id: message.channel_id,
              platform: :gchat,
              adapter_name: :gchat,
              raw: payload
            )]
          else
            [ChatSDK::Events::SubscribedMessage.new(
              message: message,
              thread_id: message.thread_id,
              channel_id: message.channel_id,
              platform: :gchat,
              adapter_name: :gchat,
              raw: payload
            )]
          end
        end

        def parse_card_clicked(payload)
          action = payload.dig("action", "actionMethodName") || payload.dig("common", "invokedFunction")
          params = payload.dig("action", "parameters") || []
          value = params.first&.dig("value")

          user_data = payload["user"] || {}
          space = payload.dig("message", "space") || payload["space"] || {}
          thread_data = payload.dig("message", "thread") || {}

          user = ChatSDK::Author.new(
            id: extract_id(user_data["name"]),
            name: user_data["displayName"] || user_data["name"] || "unknown",
            platform: :gchat
          )

          [ChatSDK::Events::Action.new(
            action_id: action || "unknown",
            value: value,
            user: user,
            thread_id: extract_id(thread_data["name"]),
            channel_id: extract_id(space["name"]),
            platform: :gchat,
            adapter_name: :gchat,
            raw: payload
          )]
        end

        def bot_mentioned?(msg_data)
          annotations = msg_data["annotations"] || []
          annotations.any? { |a| a["type"] == "USER_MENTION" && a.dig("userMention", "type") == "MENTION" }
        end

        def extract_id(resource_name)
          return resource_name unless resource_name.is_a?(String)
          resource_name.split("/").last || resource_name
        end
      end
    end
  end
end
