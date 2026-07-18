# frozen_string_literal: true

module ChatSDK
  module Events
    class Action < Base
      attr_reader :action_id, :value, :user, :thread_id, :channel_id, :trigger_id

      def initialize(action_id:, thread_id:, channel_id:, value: nil, user: nil, trigger_id: nil, **kwargs)
        super(type: :action, **kwargs)
        @action_id = action_id
        @value = value
        @user = user
        @thread_id = thread_id
        @channel_id = channel_id
        @trigger_id = trigger_id
      end
    end
  end
end
