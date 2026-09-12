# frozen_string_literal: true

module ChatSDK
  module Slack
    class EventParser
      class << self
        def parse(payload)
          case payload["type"]
          when "event_callback"
            parse_event_callback(payload)
          when "block_actions", "interactive_message"
            parse_block_actions(payload)
          when "view_submission"
            parse_view_submission(payload)
          else
            # Slash commands come as form-encoded, not wrapped in type
            if payload["command"]
              parse_slash_command(payload)
            else
              []
            end
          end
        end

        private

        def parse_event_callback(payload)
          event = payload["event"]
          return [] unless event

          case event["type"]
          when "app_mention"
            parse_mention(event, payload)
          when "message"
            parse_message_event(event, payload)
          when "reaction_added"
            parse_reaction(event, payload, added: true)
          when "reaction_removed"
            parse_reaction(event, payload, added: false)
          else
            []
          end
        end

        def parse_mention(event, payload)
          author = ChatSDK::Author.new(
            id: event["user"],
            name: event["user"],
            platform: :slack
          )
          message = ChatSDK::Message.new(
            id: event["ts"],
            text: event["text"] || "",
            author: author,
            thread_id: event["thread_ts"] || event["ts"],
            channel_id: event["channel"],
            platform: :slack,
            raw: event
          )
          [ChatSDK::Events::Mention.new(
            message: message,
            thread_id: event["thread_ts"] || event["ts"],
            channel_id: event["channel"],
            platform: :slack,
            adapter_name: :slack,
            raw: payload
          )]
        end

        def parse_message_event(event, payload)
          return parse_message_updated(event, payload) if event["subtype"] == "message_changed"
          return parse_message_deleted(event, payload) if event["subtype"] == "message_deleted"
          return [] if event["subtype"] && event["subtype"] != "file_share"
          return [] if event["bot_id"]

          author = ChatSDK::Author.new(
            id: event["user"],
            name: event["user"],
            platform: :slack
          )
          message = ChatSDK::Message.new(
            id: event["ts"],
            text: event["text"] || "",
            author: author,
            thread_id: event["thread_ts"] || event["ts"],
            channel_id: event["channel"],
            platform: :slack,
            raw: event
          )

          channel_type = event["channel_type"]
          if channel_type == "im"
            [ChatSDK::Events::DirectMessage.new(
              message: message,
              thread_id: event["thread_ts"] || event["ts"],
              channel_id: event["channel"],
              platform: :slack,
              adapter_name: :slack,
              raw: payload
            )]
          else
            [ChatSDK::Events::SubscribedMessage.new(
              message: message,
              thread_id: event["thread_ts"] || event["ts"],
              channel_id: event["channel"],
              platform: :slack,
              adapter_name: :slack,
              raw: payload
            )]
          end
        end

        def parse_message_updated(event, payload)
          return [] if event["hidden"]

          message_data = event["message"]
          return [] unless message_data

          channel_id = event["channel"] || message_data["channel"]
          message = slack_message(message_data, channel_id)
          previous = slack_message(event["previous_message"], channel_id) if event["previous_message"]
          [ChatSDK::Events::MessageUpdated.new(
            message: message,
            previous_message: previous,
            thread_id: message.thread_id,
            channel_id: channel_id,
            platform: :slack,
            adapter_name: :slack,
            raw: payload
          )]
        end

        def parse_message_deleted(event, payload)
          previous = event["previous_message"]
          message_id = event["deleted_ts"] || previous&.dig("ts")
          return [] unless message_id

          channel_id = event["channel"] || previous&.dig("channel")
          previous_message = slack_message(previous, channel_id) if previous
          thread_id = previous&.dig("thread_ts") || message_id
          [ChatSDK::Events::MessageDeleted.new(
            message_id: message_id,
            previous_message: previous_message,
            thread_id: thread_id,
            channel_id: channel_id,
            deleted_at: slack_time(event["event_ts"] || event["ts"]),
            platform: :slack,
            adapter_name: :slack,
            raw: payload
          )]
        end

        def slack_message(data, channel_id)
          user_id = data["user"] || data.dig("bot_profile", "user_id") || "unknown"
          ChatSDK::Message.new(
            id: data["ts"],
            text: data["text"] || "",
            author: ChatSDK::Author.new(
              id: user_id,
              name: data["username"] || user_id,
              platform: :slack,
              bot: !!data["bot_id"],
              system: user_id == "USLACK"
            ),
            thread_id: data["thread_ts"] || data["ts"],
            channel_id: channel_id,
            platform: :slack,
            timestamp: slack_time(data["ts"]),
            raw: data
          )
        end

        def slack_time(value)
          Time.at(Float(value)) if value
        rescue ArgumentError, TypeError
          nil
        end

        def parse_reaction(event, payload, added:)
          [ChatSDK::Events::Reaction.new(
            emoji: event["reaction"],
            user_id: event["user"],
            message_id: event.dig("item", "ts"),
            thread_id: event.dig("item", "ts"),
            channel_id: event.dig("item", "channel"),
            added: added,
            platform: :slack,
            adapter_name: :slack,
            raw: payload
          )]
        end

        def parse_block_actions(payload)
          actions = payload["actions"] || []
          user = payload["user"]
          channel = payload.dig("channel", "id")
          message_ts = payload.dig("message", "ts")
          thread_ts = payload.dig("message", "thread_ts") || message_ts
          trigger_id = payload["trigger_id"]

          actions.map do |action|
            ChatSDK::Events::Action.new(
              action_id: action["action_id"],
              value: action["value"] || action.dig("selected_option", "value"),
              user: ChatSDK::Author.new(id: user["id"], name: user["name"] || user["id"], platform: :slack),
              thread_id: thread_ts,
              channel_id: channel,
              trigger_id: trigger_id,
              platform: :slack,
              adapter_name: :slack,
              raw: payload
            )
          end
        end

        def parse_view_submission(payload)
          # View submissions are handled differently - return empty for now
          # They'll be handled via on_modal_submit in a future version
          []
        end

        def parse_slash_command(payload)
          [ChatSDK::Events::SlashCommand.new(
            command: payload["command"],
            text: payload["text"] || "",
            user_id: payload["user_id"],
            channel_id: payload["channel_id"],
            trigger_id: payload["trigger_id"],
            platform: :slack,
            adapter_name: :slack,
            raw: payload
          )]
        end
      end
    end
  end
end
