module ChatSDK
  module Events
    class SlashCommand < Base
      attr_reader :command, :text, :user_id, :channel_id, :trigger_id

      def initialize(command:, text: "", user_id:, channel_id:, trigger_id: nil, **kwargs)
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
