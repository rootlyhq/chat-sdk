# frozen_string_literal: true

module ChatSDK
  module Events
    class Mention < Base
      attr_reader :message, :thread_id, :channel_id

      def initialize(message:, thread_id:, channel_id:, **kwargs)
        super(type: :mention, **kwargs)
        @message = message
        @thread_id = thread_id
        @channel_id = channel_id
      end
    end
  end
end
