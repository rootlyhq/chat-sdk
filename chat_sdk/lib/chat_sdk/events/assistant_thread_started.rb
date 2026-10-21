# frozen_string_literal: true

module ChatSDK
  module Events
    class AssistantThreadStarted < Base
      attr_reader :thread_id, :channel_id, :thread_ts, :user_id, :context

      def initialize(thread_id:, channel_id:, thread_ts:, user_id:, context: {}, **kwargs)
        super(type: :assistant_thread_started, **kwargs)
        @thread_id = thread_id
        @channel_id = channel_id
        @thread_ts = thread_ts
        @user_id = user_id
        @context = AssistantContext.coerce(context)
      end
    end
  end
end
