# frozen_string_literal: true

module ChatSDK
  module Teams
    class ActivityParser
      class << self
        def parse(activity, bot_app_id: nil)
          return [] unless activity.is_a?(Hash)

          case activity["type"]
          when "message"
            parse_message(activity, bot_app_id)
          when "messageReaction"
            parse_message_reaction(activity)
          when "invoke"
            parse_invoke(activity)
          else
            []
          end
        end

        private

        def parse_message(activity, bot_app_id)
          return [] if activity.dig("from", "id") == bot_app_id

          author = build_author(activity)
          conversation_id = activity.dig("conversation", "id")
          thread_id = activity.dig("conversation", "id")

          message = ChatSDK::Message.new(
            id: activity["id"],
            text: activity["text"] || "",
            author: author,
            thread_id: thread_id,
            channel_id: conversation_id,
            platform: :teams,
            raw: activity
          )

          if bot_mentioned?(activity, bot_app_id)
            [ChatSDK::Events::Mention.new(
              message: message,
              thread_id: thread_id,
              channel_id: conversation_id,
              platform: :teams,
              adapter_name: :teams,
              raw: activity
            )]
          elsif activity.dig("conversation", "conversationType") == "personal"
            [ChatSDK::Events::DirectMessage.new(
              message: message,
              thread_id: thread_id,
              channel_id: conversation_id,
              platform: :teams,
              adapter_name: :teams,
              raw: activity
            )]
          else
            [ChatSDK::Events::SubscribedMessage.new(
              message: message,
              thread_id: thread_id,
              channel_id: conversation_id,
              platform: :teams,
              adapter_name: :teams,
              raw: activity
            )]
          end
        end

        def parse_message_reaction(activity)
          conversation_id = activity.dig("conversation", "id")
          events = []

          (activity["reactionsAdded"] || []).each do |reaction|
            events << ChatSDK::Events::Reaction.new(
              emoji: reaction["type"],
              user_id: activity.dig("from", "id"),
              message_id: activity["replyToId"],
              thread_id: conversation_id,
              channel_id: conversation_id,
              added: true,
              platform: :teams,
              adapter_name: :teams,
              raw: activity
            )
          end

          (activity["reactionsRemoved"] || []).each do |reaction|
            events << ChatSDK::Events::Reaction.new(
              emoji: reaction["type"],
              user_id: activity.dig("from", "id"),
              message_id: activity["replyToId"],
              thread_id: conversation_id,
              channel_id: conversation_id,
              added: false,
              platform: :teams,
              adapter_name: :teams,
              raw: activity
            )
          end

          events
        end

        def parse_invoke(activity)
          return [] unless activity.dig("value")

          conversation_id = activity.dig("conversation", "id")
          user = build_author(activity)

          action_id = activity.dig("value", "action") || activity["name"] || "invoke"
          value = activity.dig("value", "data") || activity["value"]
          value = value.is_a?(Hash) ? JSON.generate(value) : value.to_s

          [ChatSDK::Events::Action.new(
            action_id: action_id,
            value: value,
            user: user,
            thread_id: conversation_id,
            channel_id: conversation_id,
            platform: :teams,
            adapter_name: :teams,
            raw: activity
          )]
        end

        def build_author(activity)
          from = activity["from"] || {}
          ChatSDK::Author.new(
            id: from["id"] || "unknown",
            name: from["name"] || from["id"] || "unknown",
            platform: :teams,
            bot: from["role"] == "bot"
          )
        end

        def bot_mentioned?(activity, bot_app_id)
          return false unless bot_app_id

          entities = activity["entities"] || []
          entities.any? do |entity|
            entity["type"] == "mention" &&
              entity.dig("mentioned", "id") == bot_app_id
          end
        end
      end
    end
  end
end
