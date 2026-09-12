# frozen_string_literal: true

module ChatSDK
  module AI
    class << self
      def to_ai_messages(messages, include_names: false, &transform)
        Converter.to_ai_messages(messages, include_names: include_names, &transform)
      end

      def create_tools(preset: :messenger, require_approval: true)
        ToolBuilder.new(preset: preset, require_approval: require_approval).build
      end

      def create_executor(chat:, scope: nil, strict_scope: false)
        ToolExecutor.new(chat: chat, scope: scope, strict_scope: strict_scope)
      end
    end
  end
end
