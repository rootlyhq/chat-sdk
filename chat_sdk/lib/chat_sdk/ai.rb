# frozen_string_literal: true

module ChatSDK
  module AI
    class << self
      def to_ai_messages(messages, include_names: false, &transform)
        Converter.to_ai_messages(messages, include_names: include_names, &transform)
      end

      def create_tools(chat:, preset: :messenger, require_approval: true)
        ToolBuilder.new(chat: chat, preset: preset, require_approval: require_approval).build
      end
    end
  end
end
