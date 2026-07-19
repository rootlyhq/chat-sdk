# frozen_string_literal: true

module ChatSDK
  module X
    class EventParser
      class << self
        def parse(payload, bot_user_id: nil)
          return [] unless payload.is_a?(Hash)

          events = []
          events.concat(parse_mentions(payload, bot_user_id))
          events.concat(parse_direct_messages(payload, bot_user_id))
          events
        end

        private

        def parse_mentions(payload, bot_user_id)
          tweet_events = payload["tweet_create_events"] || payload.dig("post", "mention", "create") || []
          return [] unless tweet_events.is_a?(Array)

          tweet_events.filter_map do |data|
            data = data["data"] if data.key?("data")
            author_id = data["author_id"] || data.dig("user", "id_str") || data.dig("user", "id")&.to_s
            next if bot_user_id && author_id == bot_user_id

            message_id = data["id"] || data["id_str"]
            text = data["text"] || ""
            conversation_id = data["conversation_id"] || message_id

            msg = ChatSDK::Message.new(
              id: message_id&.to_s,
              text: text,
              author: ChatSDK::Author.new(id: author_id || "unknown", name: author_id || "unknown", platform: :x, bot: false),
              thread_id: "x:post:#{conversation_id}",
              channel_id: author_id,
              platform: :x,
              raw: data
            )

            ChatSDK::Events::Mention.new(
              message: msg,
              thread_id: "x:post:#{conversation_id}",
              channel_id: author_id,
              platform: :x,
              adapter_name: :x,
              raw: data
            )
          end
        end

        def parse_direct_messages(payload, bot_user_id)
          dm_events = payload["direct_message_events"] || payload.dig("dm", "received") || []
          return [] unless dm_events.is_a?(Array)

          dm_events.filter_map do |data|
            data = data["data"] if data.is_a?(Hash) && data.key?("data")
            sender_id = data["sender_id"] || data.dig("message_create", "sender_id")
            next if bot_user_id && sender_id == bot_user_id

            text = data["text"] || data.dig("message_create", "message_data", "text") || ""
            message_id = data["id"] || data["id_str"]

            msg = ChatSDK::Message.new(
              id: message_id&.to_s,
              text: text,
              author: ChatSDK::Author.new(id: sender_id || "unknown", name: sender_id || "unknown", platform: :x, bot: false),
              thread_id: "x:dm:#{sender_id}",
              channel_id: sender_id,
              platform: :x,
              raw: data
            )

            ChatSDK::Events::DirectMessage.new(
              message: msg,
              thread_id: "x:dm:#{sender_id}",
              channel_id: sender_id,
              platform: :x,
              adapter_name: :x,
              raw: data
            )
          end
        end
      end
    end
  end
end
