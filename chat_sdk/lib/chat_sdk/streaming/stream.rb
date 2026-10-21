# frozen_string_literal: true

module ChatSDK
  module Streaming
    class Stream
      include ChatSDK::Adapter::Invocation

      attr_reader :adapter, :channel_id, :thread_id, :update_interval

      def initialize(adapter:, channel_id:, thread_id:, placeholder: nil, update_interval: 0.5, ai_generated: false)
        @adapter = adapter
        @channel_id = channel_id
        @thread_id = thread_id
        @placeholder = placeholder
        @update_interval = update_interval
        @ai_generated = ai_generated
        @buffer = +""
        @delivered_text = +""
        @message_id = nil
        @message = nil
        @last_flush_at = nil
      end

      def <<(chunk)
        text = Chunk.text_of(Chunk.normalize(chunk))
        return self unless text

        @buffer << text
        maybe_flush
        self
      end

      def run(source = nil, &block)
        post_placeholder if @placeholder
        if source
          source.each { |chunk| self << chunk }
        elsif block
          block.call(self)
        end
        flush
        message_with_text(@message, @delivered_text)
      end

      private

      def message_with_text(message, text)
        return unless message

        ChatSDK::Message.new(
          id: message.id,
          text: text.dup,
          author: message.author,
          thread_id: message.thread_id,
          channel_id: message.channel_id,
          platform: message.platform,
          attachments: message.attachments,
          links: message.links,
          reply_to: message.reply_to,
          subject: message.subject,
          raw: message.raw,
          timestamp: message.timestamp,
          is_mention: message.is_mention
        )
      end

      def post_placeholder
        result = adapter.post_message(
          channel_id: channel_id,
          message: PostableMessage.new(text: @placeholder, ai_generated: @ai_generated),
          thread_id: thread_id
        )
        @delivered_text = @placeholder.dup
        @message = result if result.is_a?(ChatSDK::Message)
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
          call_adapter(
            :edit_message,
            channel_id: channel_id,
            message_id: @message_id,
            message: PostableMessage.new(text: @buffer.dup, ai_generated: @ai_generated),
            thread_id: thread_id
          )
          @delivered_text = @buffer.dup
        elsif !@message_id
          result = adapter.post_message(
            channel_id: channel_id,
            message: PostableMessage.new(text: @buffer.dup, ai_generated: @ai_generated),
            thread_id: thread_id
          )
          @message = result if result.is_a?(ChatSDK::Message)
          @message_id = result.id if result.respond_to?(:id)
          @delivered_text = @buffer.dup
        end

        @last_flush_at = Time.now.to_f
      end
    end
  end
end
