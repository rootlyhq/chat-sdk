class ChatChannel < ApplicationCable::Channel
  def subscribed
    @channel_id = params[:channel_id] || "default"
    stream_from "chat_sdk_web_#{@channel_id}"
  end

  def receive(data)
    text = data["message"].to_s.strip
    return if text.empty?

    user_id = data["user_id"] || "guest"
    user_name = data["user_name"] || "Guest"

    author = ChatSDK::Author.new(id: user_id, name: user_name, platform: :web)
    message = ChatSDK::Message.new(
      id: SecureRandom.uuid, text: text, author: author,
      thread_id: @channel_id, channel_id: @channel_id, platform: :web
    )

    # Broadcast user's message
    html = ApplicationController.render(partial: "chat/message", locals: { message: message, from_bot: false })
    ActionCable.server.broadcast("chat_sdk_web_#{@channel_id}", html)

    # Dispatch to ChatSDK bot
    event = ChatSDK::Events::Mention.new(
      message: message, thread_id: @channel_id, channel_id: @channel_id,
      platform: :web, adapter_name: :web
    )
    ChatBot.instance.dispatch(event, adapter_name: :web)
  end
end
