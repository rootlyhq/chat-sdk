# frozen_string_literal: true

module ChatSDK
  module WhatsApp
    class EventParser
      class << self
        def parse(payload, phone_number_id)
          return [] unless payload.is_a?(Hash)
          return [] unless payload["object"] == "whatsapp_business_account"

          (payload["entry"] || [])
            .flat_map { |entry| entry["changes"] || [] }
            .select { |change| change["field"] == "messages" }
            .flat_map { |change| change.dig("value", "messages") || [] }
            .filter_map { |msg| parse_message(msg, phone_number_id) }
        end

        private

        def parse_message(msg, phone_number_id)
          from = msg["from"]&.to_s
          return nil unless from

          author = ChatSDK::Author.new(id: from, name: from, platform: :whatsapp, bot: false)
          thread_id = "whatsapp:#{phone_number_id}:#{from}"

          case msg["type"]
          when "text"
            build_direct_message(msg, msg.dig("text", "body") || "", author, from, thread_id)
          when "interactive"
            parse_interactive_message(msg, author, from, thread_id)
          when "reaction"
            parse_reaction_message(msg, from, thread_id)
          when "image", "document", "audio", "video", "sticker"
            parse_media_message(msg, author, from, thread_id)
          end
        end

        def parse_reaction_message(msg, from, thread_id)
          reaction = msg["reaction"] || {}
          emoji = reaction["emoji"] || ""

          ChatSDK::Events::Reaction.new(
            emoji: emoji,
            added: !emoji.empty?,
            user_id: from,
            message_id: reaction["message_id"],
            thread_id: thread_id,
            channel_id: from,
            platform: :whatsapp,
            adapter_name: :whatsapp,
            raw: msg
          )
        end

        def parse_interactive_message(msg, author, channel_id, thread_id)
          interactive = msg["interactive"] || {}
          action_id = interactive.dig("button_reply", "id") || interactive.dig("list_reply", "id") || ""

          ChatSDK::Events::Action.new(
            action_id: action_id,
            value: action_id,
            user: author,
            thread_id: thread_id,
            channel_id: channel_id,
            platform: :whatsapp,
            adapter_name: :whatsapp,
            raw: msg
          )
        end

        def parse_media_message(msg, author, channel_id, thread_id)
          media_type = msg["type"]
          media_data = msg[media_type] || {}
          caption = media_data["caption"] || ""
          mime_type = media_data["mime_type"] || ""
          media_id = media_data["id"] || ""

          text = [caption, "[#{media_type}: #{mime_type} #{media_id}]"].reject(&:empty?).join("\n")
          build_direct_message(msg, text, author, channel_id, thread_id)
        end

        def build_direct_message(msg, text, author, channel_id, thread_id)
          message = ChatSDK::Message.new(
            id: msg["id"],
            text: text,
            author: author,
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
