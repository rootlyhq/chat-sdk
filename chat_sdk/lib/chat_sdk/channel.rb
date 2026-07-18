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

    def ==(other)
      other.is_a?(Channel) && id == other.id
    end
    alias eql? ==

    def hash
      id.hash
    end
  end
end
