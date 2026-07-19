require "chat_sdk"

module ChatSDK
  module Web
    class Adapter < ChatSDK::Adapter::Base
      capabilities :edit_messages, :delete_messages, :streaming_edit, :direct_messages

      def name = :web
      def client = nil
      def verify_request!(_r) = true
      def parse_events(_r) = []
      def open_dm(user_id) = "web:dm:#{user_id}"
      def mention(user_id) = "@#{user_id}"

      def post_message(channel_id:, message:, thread_id: nil)
        msg = ChatSDK::PostableMessage.from(message)
        result = ChatSDK::Message.new(
          id: SecureRandom.uuid, text: msg.text || msg.card&.fallback_text || "",
          author: ChatSDK::Author.new(id: "bot", name: "Bot", platform: :web, bot: true),
          thread_id: thread_id || channel_id, channel_id: channel_id, platform: :web
        )
        html = ApplicationController.render(partial: "chat/message", locals: { message: result, from_bot: true })
        ActionCable.server.broadcast("chat_sdk_web_#{channel_id}", html)
        result
      end

      def edit_message(channel_id:, message_id:, message:)
        msg = ChatSDK::PostableMessage.from(message)
        result = ChatSDK::Message.new(
          id: message_id, text: msg.text || "",
          author: ChatSDK::Author.new(id: "bot", name: "Bot", platform: :web, bot: true),
          thread_id: channel_id, channel_id: channel_id, platform: :web
        )
        html = ApplicationController.render(partial: "chat/message", locals: { message: result, from_bot: true })
        turbo = %(<turbo-stream action="replace" target="message-#{message_id}"><template>#{html}</template></turbo-stream>)
        ActionCable.server.broadcast("chat_sdk_web_#{channel_id}", turbo)
      end

      def delete_message(channel_id:, message_id:)
        turbo = %(<turbo-stream action="remove" target="message-#{message_id}"></turbo-stream>)
        ActionCable.server.broadcast("chat_sdk_web_#{channel_id}", turbo)
      end
    end
  end
end

module ChatBot
  def self.instance
    @instance ||= begin
      bot = ChatSDK::Chat.new(
        user_name: "demo-bot",
        adapters: { web: ChatSDK::Web::Adapter.new },
        state: ChatSDK::State::Memory.new
      )

      bot.on_new_mention do |thread, message|
        thread.post("Hello #{message.author.name}! You said: #{message.text}")
      end

      bot.on_new_message(/deploy/i) do |thread, message|
        card = ChatSDK.card(title: "Deploy Request") do
          text "Requested by #{message.author.name}"
          fields { field "Command", message.text }
          actions do
            button "Approve", id: "deploy_approve", style: :primary
            button "Reject", id: "deploy_reject", style: :danger
          end
        end
        thread.post(card)
      end

      bot
    end
  end
end
