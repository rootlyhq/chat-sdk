# frozen_string_literal: true

module ChatSDK
  module Discord
    class EventParser
      class << self
        def parse(payload)
          return [] unless payload.is_a?(Hash)

          type = payload["type"]
          data = payload["data"] || {}

          case type
          when 1 # PING
            []
          when 2 # APPLICATION_COMMAND
            parse_application_command(payload, data)
          when 3 # MESSAGE_COMPONENT
            parse_message_component(payload, data)
          else
            []
          end
        end

        private

        def parse_application_command(payload, data)
          user_info = extract_user(payload)
          channel_id = payload["channel_id"]
          command = "/#{data["name"]}"
          text = extract_options_text(data["options"])

          [ChatSDK::Events::SlashCommand.new(
            command: command,
            text: text,
            user_id: user_info[:id],
            channel_id: channel_id,
            trigger_id: payload["id"],
            platform: :discord,
            adapter_name: :discord,
            raw: payload
          )]
        end

        def parse_message_component(payload, data)
          user_info = extract_user(payload)
          channel_id = payload["channel_id"]
          message_id = payload.dig("message", "id")

          action_id = data["custom_id"]
          value = if data["values"].is_a?(Array) && !data["values"].empty?
            data["values"].first
          else
            data["custom_id"]
          end

          user = ChatSDK::Author.new(
            id: user_info[:id],
            name: user_info[:name],
            platform: :discord,
            bot: false
          )

          [ChatSDK::Events::Action.new(
            action_id: action_id,
            value: value,
            user: user,
            thread_id: message_id,
            channel_id: channel_id,
            platform: :discord,
            adapter_name: :discord,
            raw: payload
          )]
        end

        def extract_user(payload)
          user = payload.dig("member", "user") || payload["user"] || {}
          {
            id: user["id"] || "unknown",
            name: user["username"] || user["id"] || "unknown"
          }
        end

        def extract_options_text(options)
          return "" unless options.is_a?(Array)

          options.filter_map { |opt| opt["value"]&.to_s }.join(" ")
        end
      end
    end
  end
end
