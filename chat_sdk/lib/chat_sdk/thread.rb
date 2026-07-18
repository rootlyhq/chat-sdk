# frozen_string_literal: true

module ChatSDK
  class Thread
    attr_reader :id, :channel_id, :adapter, :chat

    def initialize(id:, channel_id:, adapter:, chat:)
      @id = id
      @channel_id = channel_id
      @adapter = adapter
      @chat = chat
    end

    def subscribe
      chat.state.subscribe(state_key)
    end

    def unsubscribe
      chat.state.unsubscribe(state_key)
    end

    def subscribed?
      chat.state.subscribed?(state_key)
    end

    def post(content)
      message = PostableMessage.from(content)
      adapter.post_message(channel_id: channel_id, message: message, thread_id: id)
    end

    def post_ephemeral(content, user_id:)
      message = PostableMessage.from(content)
      adapter.post_ephemeral(channel_id: channel_id, user_id: user_id, message: message, thread_id: id)
    end

    def post_stream(placeholder: nil, &block)
      stream = Streaming::Stream.new(
        adapter: adapter,
        channel_id: channel_id,
        thread_id: id,
        placeholder: placeholder,
        update_interval: chat.config.streaming_update_interval
      )
      stream.run(&block)
    end

    def edit(message_id, content)
      message = PostableMessage.from(content)
      adapter.edit_message(channel_id: channel_id, message_id: message_id, message: message)
    end

    def delete(message_id)
      adapter.delete_message(channel_id: channel_id, message_id: message_id)
    end

    def react(message_id, emoji)
      adapter.add_reaction(channel_id: channel_id, message_id: message_id, emoji: emoji)
    end

    def unreact(message_id, emoji)
      adapter.remove_reaction(channel_id: channel_id, message_id: message_id, emoji: emoji)
    end

    def upload(io:, filename:, comment: nil)
      adapter.upload_file(channel_id: channel_id, io: io, filename: filename, thread_id: id, comment: comment)
    end

    def messages(cursor: nil, limit: 50)
      adapter.fetch_messages(channel_id: channel_id, thread_id: id, cursor: cursor, limit: limit)
    end

    def state
      chat.state.get(state_key(:state))
    end

    def set_state(value)
      chat.state.set(state_key(:state), value, ttl: 30 * 24 * 3600)
    end

    def mention_user(user_id)
      adapter.mention(user_id)
    end

    def open_modal(trigger_id:, modal:)
      adapter.open_modal(trigger_id: trigger_id, modal: modal)
    end

    def ==(other)
      other.is_a?(ChatSDK::Thread) && id == other.id && channel_id == other.channel_id
    end
    alias_method :eql?, :==

    def hash
      [id, channel_id].hash
    end

    private

    def state_key(suffix = nil)
      base = "#{adapter.name}:#{channel_id}:#{id}"
      suffix ? "#{base}:#{suffix}" : base
    end
  end
end
