# frozen_string_literal: true

module ChatSDK
  module Events
    class MessageDeleted < Base
      attr_reader :message_id, :previous_message, :thread_id, :channel_id, :deleted_at
      attr_accessor :thread

      def initialize(message_id:, thread_id:, channel_id:, previous_message: nil, deleted_at: nil, **kwargs)
        super(type: :message_deleted, **kwargs)
        @message_id = message_id
        @previous_message = previous_message
        @thread_id = thread_id
        @channel_id = channel_id
        @deleted_at = deleted_at
      end
    end
  end
end
