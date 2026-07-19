# frozen_string_literal: true

# ChatSDK Web Adapter
#
# A lightweight adapter for browser-based chat via ActionCable.
# Unlike platform adapters (Slack, Teams) it does not verify webhooks or parse
# HTTP requests -- messages arrive through ActionCable's ChatChannel and
# replies are broadcast as HTML partials.
module ChatSDK
  module Web
    class Adapter < ChatSDK::Adapter::Base
      capabilities :edit_messages, :delete_messages, :streaming_edit, :direct_messages

      def name
        :web
      end

      def client
        nil # No external API client needed
      end

      # Inbound -- handled by ActionCable, not rack webhooks
      def verify_request!(_rack_request)  = true
      def parse_events(_rack_request)     = []

      # Outbound -- broadcast Turbo-style HTML via ActionCable
      def post_message(channel_id:, message:, thread_id: nil)
        msg = ChatSDK::PostableMessage.from(message)
        message_id = SecureRandom.uuid

        result = ChatSDK::Message.new(
          id:         message_id,
          text:       msg.text || "",
          author:     ChatSDK::Author.new(id: "bot", name: "bot", platform: :web, bot: true),
          thread_id:  thread_id || channel_id,
          channel_id: channel_id,
          platform:   :web
        )

        broadcast_message(channel_id, result, from_bot: true)
        result
      end

      def edit_message(channel_id:, message_id:, message:)
        msg = ChatSDK::PostableMessage.from(message)
        result = ChatSDK::Message.new(
          id:         message_id,
          text:       msg.text || "",
          author:     ChatSDK::Author.new(id: "bot", name: "bot", platform: :web, bot: true),
          thread_id:  channel_id,
          channel_id: channel_id,
          platform:   :web
        )

        html = ApplicationController.render(
          partial: "chat/message",
          locals:  { message: result, from_bot: true }
        )
        # Wrap in a Turbo Stream replace so the client swaps the existing message
        turbo_html = <<~HTML
          <turbo-stream action="replace" target="message-#{message_id}">
            <template>#{html}</template>
          </turbo-stream>
        HTML
        ActionCable.server.broadcast("chat_sdk_web_#{channel_id}", turbo_html)
      end

      def delete_message(channel_id:, message_id:)
        turbo_html = <<~HTML
          <turbo-stream action="remove" target="message-#{message_id}">
          </turbo-stream>
        HTML
        ActionCable.server.broadcast("chat_sdk_web_#{channel_id}", turbo_html)
      end

      def open_dm(user_id)
        "web:dm:#{user_id}"
      end

      def mention(user_id)
        "@#{user_id}"
      end

      private

      def broadcast_message(channel_id, message, from_bot:)
        html = ApplicationController.render(
          partial: "chat/message",
          locals:  { message: message, from_bot: from_bot }
        )
        ActionCable.server.broadcast("chat_sdk_web_#{channel_id}", html)
      end
    end
  end
end

# Build the bot with the web adapter and in-memory state.
module ChatBot
  def self.instance
    @instance ||= begin
      web   = ChatSDK::Web::Adapter.new
      state = ChatSDK::State::Memory.new

      bot = ChatSDK::Chat.new(
        user_name: "demo-bot",
        adapters:  { web: web },
        state:     state,
        log_level: :debug
      )

      # Echo handler -- respond to every mention
      bot.on_new_mention do |thread, message|
        thread.post("Hello, #{message.author.name}! You said: #{message.text}")
      end

      # Pattern-matched handler -- respond to "deploy" with a card
      bot.on_new_message(/deploy/i) do |thread, message|
        card = ChatSDK.card(title: "Deploy Request") do
          text "Requested by #{message.author.name}"
          fields do
            field "Command", message.text
          end
          actions do
            button "Approve", id: "deploy_approve", style: :primary
            button "Reject",  id: "deploy_reject",  style: :danger
          end
        end
        thread.post(card)
      end

      bot
    end
  end
end
