# frozen_string_literal: true

module ChatSDK
  module Events
    class MemberJoinedChannel < Base
      attr_reader :user_id, :channel_id, :inviter_id

      def initialize(user_id:, channel_id:, inviter_id: nil, **kwargs)
        super(type: :member_joined_channel, **kwargs)
        @user_id = user_id
        @channel_id = channel_id
        @inviter_id = inviter_id
      end
    end
  end
end
