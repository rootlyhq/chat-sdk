# frozen_string_literal: true

module ChatSDK
  module Teams
    class ActivityParser
      class << self
        def parse(activity, bot_app_id: nil)
          return [] unless activity.is_a?(Hash)

          case activity["type"]
          when "message"
            if action_submission?(activity)
              parse_invoke(activity, bot_app_id)
            else
              parse_message(activity, bot_app_id)
            end
          when "messageReaction"
            parse_message_reaction(activity)
          when "invoke"
            parse_invoke(activity, bot_app_id)
          when "installationUpdate"
            parse_installation(activity, bot_app_id)
          else
            []
          end
        end

        private

        def parse_message(activity, bot_app_id)
          return [] if self_message?(activity, bot_app_id)

          author = build_author(activity, bot_app_id)
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

        def parse_invoke(activity, bot_app_id)
          return [] unless activity.dig("value")

          conversation_id = activity.dig("conversation", "id")
          user = build_author(activity, bot_app_id)

          nested_data = activity.dig("value", "data")
          action_data = activity.dig("value", "action")
          nested_action_data = action_data.is_a?(Hash) ? action_data["data"] : nil
          data = if nested_data.is_a?(Hash)
            nested_data
          elsif nested_action_data.is_a?(Hash)
            nested_action_data
          else
            activity["value"]
          end
          data = {} unless data.is_a?(Hash)
          action = activity.dig("value", "action")
          action_id = data["actionId"] || data["action"] ||
            (action unless action.is_a?(Hash)) || activity["name"] || "invoke"
          value = data["value"] || (nested_data unless nested_data.is_a?(Hash)) || data
          value = value.is_a?(Hash) ? JSON.generate(value) : value.to_s

          [ChatSDK::Events::Action.new(
            action_id: action_id,
            value: value,
            values: action_values(data),
            user: user,
            thread_id: conversation_id,
            channel_id: conversation_id,
            platform: :teams,
            adapter_name: :teams,
            raw: activity
          )]
        end

        def action_submission?(activity)
          value = activity["value"]
          value.is_a?(Hash) && (value.key?("data") || value.key?("action") || value.key?("actionId"))
        end

        def parse_installation(activity, bot_app_id)
          return [] unless app_id?(activity.dig("recipient", "id"), bot_app_id)

          action = activity["action"]
          event_class = case action
          when "add", "add-upgrade" then ChatSDK::Events::Installed
          when "remove", "remove-upgrade" then ChatSDK::Events::Uninstalled
          else return []
          end

          conversation_id = activity.dig("conversation", "id")
          return [] unless conversation_id

          team_id = activity.dig("channelData", "team", "id")
          tenant_id = activity.dig("conversation", "tenantId") ||
            activity.dig("channelData", "tenant", "id")
          [event_class.new(
            installation_id: team_id || tenant_id || conversation_id,
            team_id: team_id,
            tenant_id: tenant_id,
            conversation_id: conversation_id,
            action: action,
            user: build_author(activity, bot_app_id),
            platform: :teams,
            adapter_name: :teams,
            raw: activity
          )]
        end

        def build_author(activity, bot_app_id)
          from = activity["from"] || {}
          from_id = from["id"] || "unknown"
          ChatSDK::Author.new(
            id: from_id,
            name: from["name"] || from_id,
            platform: :teams,
            bot: from["role"].to_s.downcase == "bot" || from_id.start_with?("28:"),
            me: self_message?(activity, bot_app_id),
            locale: activity["locale"]
          )
        end

        def self_message?(activity, bot_app_id)
          from_id = activity.dig("from", "id")
          return true if app_id?(from_id, bot_app_id)

          recipient_id = activity.dig("recipient", "id")
          from_id && recipient_id && from_id == recipient_id
        end

        def app_id?(id, bot_app_id)
          return false unless id && bot_app_id

          id == bot_app_id || id == "28:#{bot_app_id}"
        end

        def action_values(data)
          values = data.except("action", "actionId", "value", "msteams")
          values.empty? ? nil : values
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
