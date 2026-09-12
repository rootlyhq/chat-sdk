# frozen_string_literal: true

module ChatSDK
  module Events
    class MessageUpdated < Base
      attr_reader :message, :previous_message, :thread_id, :channel_id

      def initialize(message:, thread_id:, channel_id:, previous_message: nil, **kwargs)
        super(type: :message_updated, **kwargs)
        @message = message
        @previous_message = previous_message
        @thread_id = thread_id
        @channel_id = channel_id
      end
    end
  end
end
