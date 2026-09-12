# frozen_string_literal: true

module ChatSDK
  class Channel
    attr_reader :id, :adapter, :chat

    def initialize(id:, adapter:, chat:)
      @id = id
      @adapter = adapter
      @chat = chat
    end

    def post(content)
      message = PostableMessage.from(content)
      adapter.post_message(channel_id: id, message: message)
    end

    def thread(thread_id)
      ChatSDK::Thread.new(id: thread_id, channel_id: id, adapter: adapter, chat: chat)
    end

    def messages(cursor: nil, limit: 50)
      adapter.fetch_channel_messages(channel_id: id, cursor: cursor, limit: limit)
    end

    def threads(cursor: nil, limit: 50)
      adapter.list_threads(channel_id: id, cursor: cursor, limit: limit)
    end

    def ==(other)
      other.is_a?(Channel) && id == other.id
    end
    alias_method :eql?, :==

    def hash
      id.hash
    end
  end
end
