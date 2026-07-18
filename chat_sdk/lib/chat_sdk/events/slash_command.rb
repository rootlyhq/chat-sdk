# frozen_string_literal: true

module ChatSDK
  module Events
    class SlashCommand < Base
      attr_reader :command, :text, :user_id, :channel_id, :trigger_id
      attr_accessor :thread

      def initialize(command:, user_id:, channel_id:, text: "", trigger_id: nil, **kwargs)
        super(type: :slash_command, **kwargs)
        @command = command
        @text = text
        @user_id = user_id
        @channel_id = channel_id
        @trigger_id = trigger_id
      end
    end
  end
end
