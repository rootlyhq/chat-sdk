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
          when "slash_commands"
            parse_slash_command(payload)
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
