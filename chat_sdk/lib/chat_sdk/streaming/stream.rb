module ChatSDK
  module Streaming
    class Stream
      attr_reader :adapter, :channel_id, :thread_id, :update_interval

      def initialize(adapter:, channel_id:, thread_id:, placeholder: nil, update_interval: 0.5)
        @adapter = adapter
        @channel_id = channel_id
        @thread_id = thread_id
        @placeholder = placeholder
        @update_interval = update_interval
        @buffer = +""
        @message_id = nil
        @last_flush_at = nil
      end

      def <<(chunk)
        @buffer << chunk.to_s
        maybe_flush
        self
      end

      def run(&block)
        post_placeholder if @placeholder
        yield self
        flush
      end

      private

      def post_placeholder
        result = adapter.post_message(
          channel_id: channel_id,
          message: PostableMessage.new(text: @placeholder),
          thread_id: thread_id
        )
        @message_id = result.id if result.respond_to?(:id)
      end

      def maybe_flush
        return unless @message_id
        return if @last_flush_at && (Time.now.to_f - @last_flush_at) < update_interval

        flush
      end

      def flush
        return if @buffer.empty?

        if @message_id && adapter.supports?(:edit_messages)
          adapter.edit_message(
            channel_id: channel_id,
            message_id: @message_id,
            message: PostableMessage.new(text: @buffer.dup)
          )
        elsif !@message_id
          result = adapter.post_message(
            channel_id: channel_id,
            message: PostableMessage.new(text: @buffer.dup),
            thread_id: thread_id
          )
          @message_id = result.id if result.respond_to?(:id)
        end

        @last_flush_at = Time.now.to_f
      end
    end
  end
end
