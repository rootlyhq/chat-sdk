# frozen_string_literal: true

module ChatSDK
  module WhatsApp
    class EventParser
      class << self
        def parse(payload, phone_number_id)
          return [] unless payload.is_a?(Hash)
          return [] unless payload["object"] == "whatsapp_business_account"

          events = []

          (payload["entry"] || []).each do |entry|
            (entry["changes"] || []).each do |change|
              next unless change["field"] == "messages"

              value = change["value"]
              next unless value

              (value["messages"] || []).each do |msg|
                event = parse_message(msg, phone_number_id)
                events << event if event
              end
            end
          end

          events
        end

        private

        def parse_message(msg, phone_number_id)
          from = msg["from"]&.to_s
          return nil unless from

          msg_id = msg["id"]
          channel_id = from
          thread_id = "whatsapp:#{phone_number_id}:#{from}"

          case msg["type"]
          when "text"
            parse_text_message(msg, from, msg_id, channel_id, thread_id)
          when "interactive"
            parse_interactive_message(msg, from, channel_id, thread_id)
          when "image", "document", "audio", "video"
            parse_media_message(msg, from, msg_id, channel_id, thread_id)
          end
        end

        def parse_text_message(msg, from, msg_id, channel_id, thread_id)
          text = msg.dig("text", "body") || ""

          message = ChatSDK::Message.new(
            id: msg_id,
            text: text,
            author: ChatSDK::Author.new(id: from, name: from, platform: :whatsapp, bot: false),
            thread_id: thread_id,
            channel_id: channel_id,
            platform: :whatsapp,
            raw: msg
          )

          ChatSDK::Events::DirectMessage.new(
            message: message,
            thread_id: thread_id,
            channel_id: channel_id,
            platform: :whatsapp,
            adapter_name: :whatsapp,
            raw: msg
          )
        end

        def parse_interactive_message(msg, from, channel_id, thread_id)
          interactive = msg["interactive"] || {}
          button_reply = interactive["button_reply"]
          list_reply = interactive["list_reply"]

          action_id = button_reply&.dig("id") || list_reply&.dig("id") || ""
          value = action_id

          user = ChatSDK::Author.new(
            id: from,
            name: from,
            platform: :whatsapp,
            bot: false
          )

          ChatSDK::Events::Action.new(
            action_id: action_id,
            value: value,
            user: user,
            thread_id: thread_id,
            channel_id: channel_id,
            platform: :whatsapp,
            adapter_name: :whatsapp,
            raw: msg
          )
        end

        def parse_media_message(msg, from, msg_id, channel_id, thread_id)
          media_type = msg["type"]
          media_data = msg[media_type] || {}
          caption = media_data["caption"] || ""
          mime_type = media_data["mime_type"] || ""
          media_id = media_data["id"] || ""

          text = [caption, "[#{media_type}: #{mime_type} #{media_id}]"].reject(&:empty?).join("\n")

          message = ChatSDK::Message.new(
            id: msg_id,
            text: text,
            author: ChatSDK::Author.new(id: from, name: from, platform: :whatsapp, bot: false),
            thread_id: thread_id,
            channel_id: channel_id,
            platform: :whatsapp,
            raw: msg
          )

          ChatSDK::Events::DirectMessage.new(
            message: message,
            thread_id: thread_id,
            channel_id: channel_id,
            platform: :whatsapp,
            adapter_name: :whatsapp,
            raw: msg
          )
        end
      end
    end
  end
end
