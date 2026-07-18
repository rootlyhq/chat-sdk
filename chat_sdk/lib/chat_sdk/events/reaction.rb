module ChatSDK
  module Events
    class Reaction < Base
      attr_reader :emoji, :user_id, :message_id, :thread_id, :channel_id, :added

      def initialize(emoji:, user_id:, message_id:, thread_id:, channel_id:, added: true, **kwargs)
        super(type: :reaction, **kwargs)
        @emoji = emoji
        @user_id = user_id
        @message_id = message_id
        @thread_id = thread_id
        @channel_id = channel_id
        @added = added
      end

      def added?
        @added
      end

      def removed?
        !@added
      end
    end
  end
end
