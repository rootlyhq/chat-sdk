# frozen_string_literal: true

module ChatSDK
  module Messenger
    class EventParser
      class << self
        def parse(payload, bot_page_id: nil)
          return [] unless payload.is_a?(Hash)
          return [] unless payload["object"] == "page"

          events = []

          (payload["entry"] || []).each do |entry|
            (entry["messaging"] || []).each do |messaging|
              event = parse_messaging(messaging, bot_page_id: bot_page_id)
              events << event if event
            end
          end

          events
        end

        private

        def parse_messaging(messaging, bot_page_id: nil)
          sender_id = messaging.dig("sender", "id")&.to_s
          return nil unless sender_id
          return nil if bot_page_id && sender_id == bot_page_id

          channel_id = sender_id
          thread_id = "messenger:#{sender_id}"

          if messaging["reaction"]
            parse_reaction(messaging, sender_id, channel_id, thread_id)
          elsif messaging["postback"]
            parse_postback(messaging, sender_id, channel_id, thread_id)
          elsif messaging["message"]
            parse_message(messaging, sender_id, channel_id, thread_id)
          end
        end

        def parse_message(messaging, sender_id, channel_id, thread_id)
          message_data = messaging["message"]
          text = message_data["text"] || ""

          attachments = extract_attachments(message_data["attachments"])

          if !attachments.empty?
            text = [text, *attachments.map { |a| a[:url] }].reject(&:empty?).join("\n")
          end

          msg = ChatSDK::Message.new(
            id: message_data["mid"],
            text: text,
            author: ChatSDK::Author.new(id: sender_id, name: sender_id, platform: :messenger, bot: false),
            thread_id: thread_id,
            channel_id: channel_id,
            platform: :messenger,
            raw: messaging
          )

          ChatSDK::Events::DirectMessage.new(
            message: msg,
            thread_id: thread_id,
            channel_id: channel_id,
            platform: :messenger,
            adapter_name: :messenger,
            raw: messaging
          )
        end

        def parse_reaction(messaging, sender_id, channel_id, thread_id)
          reaction = messaging["reaction"]

          ChatSDK::Events::Reaction.new(
            emoji: reaction["emoji"],
            added: reaction["action"] == "react",
            user_id: sender_id,
            message_id: reaction["mid"],
            thread_id: thread_id,
            channel_id: channel_id,
            platform: :messenger,
            adapter_name: :messenger,
            raw: messaging
          )
        end

        def parse_postback(messaging, sender_id, channel_id, thread_id)
          postback = messaging["postback"]
          payload = postback["payload"] || ""

          user = ChatSDK::Author.new(
            id: sender_id,
            name: sender_id,
            platform: :messenger,
            bot: false
          )

          ChatSDK::Events::Action.new(
            action_id: payload,
            value: payload,
            user: user,
            thread_id: thread_id,
            channel_id: channel_id,
            platform: :messenger,
            adapter_name: :messenger,
            raw: messaging
          )
        end

        def extract_attachments(attachments)
          return [] unless attachments.is_a?(Array)

          attachments.filter_map do |attachment|
            url = attachment.dig("payload", "url")
            next unless url

            {type: attachment["type"], url: url}
          end
        end
      end
    end
  end
end
