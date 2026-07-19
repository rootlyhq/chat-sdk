# frozen_string_literal: true

# ActionCable channel for ChatSDK web chat.
#
# Clients subscribe with a channel_id and send messages as JSON.
# The channel broadcasts user messages back as HTML, then dispatches
# a ChatSDK::Events::Mention so registered bot handlers can respond.
class ChatChannel < ApplicationCable::Channel
  def subscribed
    @channel_id = params[:channel_id] || "default"
    stream_from stream_name
  end

  def receive(data)
    text      = data["message"].to_s.strip
    user_id   = data["user_id"]   || "anonymous"
    user_name = data["user_name"] || "Guest"
    return if text.empty?

    message_id = SecureRandom.uuid

    author = ChatSDK::Author.new(id: user_id, name: user_name, platform: :web)
    message = ChatSDK::Message.new(
      id:         message_id,
      text:       text,
      author:     author,
      thread_id:  @channel_id,
      channel_id: @channel_id,
      platform:   :web
    )

    # Broadcast the user's message to all subscribers
    broadcast_message(message, from_bot: false)

    # Dispatch to ChatSDK handlers
    event = ChatSDK::Events::Mention.new(
      message:      message,
      thread_id:    @channel_id,
      channel_id:   @channel_id,
      platform:     :web,
      adapter_name: :web
    )

    ChatBot.instance.dispatch(event, adapter_name: :web)
  end

  private

  def stream_name
    "chat_sdk_web_#{@channel_id}"
  end

  def broadcast_message(message, from_bot:)
    html = ApplicationController.render(
      partial: "chat/message",
      locals:  { message: message, from_bot: from_bot }
    )
    ActionCable.server.broadcast(stream_name, html)
  end
end
