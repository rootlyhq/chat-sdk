# frozen_string_literal: true

module ChatSDK
  module Mattermost
    class EventParser
      class << self
        def parse(payload, bot_user_id: nil)
          return [] unless payload.is_a?(Hash)

          if payload.key?("trigger_word") || payload.key?("token")
            parse_outgoing_webhook(payload, bot_user_id)
          elsif payload.key?("context") && (payload.key?("type") || payload.key?("action"))
            parse_interactive_action(payload)
          else
            []
          end
        end

        private

        def parse_outgoing_webhook(payload, bot_user_id)
          return [] if bot_user_id && payload["user_id"] == bot_user_id

          author = ChatSDK::Author.new(
            id: payload["user_id"] || "unknown",
            name: payload["user_name"] || payload["user_id"] || "unknown",
            platform: :mattermost,
            bot: false
          )

          channel_id = payload["channel_id"]
          thread_id = payload["root_id"].to_s.empty? ? nil : payload["root_id"]

          message = ChatSDK::Message.new(
            id: payload["post_id"] || "unknown",
            text: payload["text"] || "",
            author: author,
            thread_id: thread_id || payload["post_id"],
            channel_id: channel_id,
            platform: :mattermost,
            raw: payload
          )

          if payload["trigger_word"].to_s.start_with?("@")
            [ChatSDK::Events::Mention.new(
              message: message,
              thread_id: thread_id || payload["post_id"],
              channel_id: channel_id,
              platform: :mattermost,
              adapter_name: :mattermost,
              raw: payload
            )]
          else
            [ChatSDK::Events::SubscribedMessage.new(
              message: message,
              thread_id: thread_id || payload["post_id"],
              channel_id: channel_id,
              platform: :mattermost,
              adapter_name: :mattermost,
              raw: payload
            )]
          end
        end

        def parse_interactive_action(payload)
          user = ChatSDK::Author.new(
            id: payload["user_id"] || "unknown",
            name: payload["user_name"] || payload["user_id"] || "unknown",
            platform: :mattermost,
            bot: false
          )

          channel_id = payload["channel_id"]
          context = payload["context"] || {}
          action_id = context["action"] || payload["action"] || "unknown"

          value = if payload["type"] == "select"
            payload["selected_option"]
          else
            context["value"]
          end
          value = value.is_a?(Hash) ? JSON.generate(value) : value.to_s

          [ChatSDK::Events::Action.new(
            action_id: action_id,
            value: value,
            user: user,
            thread_id: payload["post_id"],
            channel_id: channel_id,
            platform: :mattermost,
            adapter_name: :mattermost,
            raw: payload
          )]
        end
      end
    end
  end
end
