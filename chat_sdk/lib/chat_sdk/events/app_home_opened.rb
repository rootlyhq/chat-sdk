# frozen_string_literal: true

module ChatSDK
  module Events
    class AppHomeOpened < Base
      attr_reader :user_id, :channel_id, :tab

      def initialize(user_id:, channel_id:, tab: nil, **kwargs)
        super(type: :app_home_opened, **kwargs)
        @user_id = user_id
        @channel_id = channel_id
        @tab = tab
      end
    end
  end
end
