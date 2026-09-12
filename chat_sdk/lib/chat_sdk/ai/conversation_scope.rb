# frozen_string_literal: true

module ChatSDK
  module AI
    module ConversationScope
      THREAD_KEY = :chat_sdk_ai_conversation_scope

      class << self
        def current
          ::Thread.current[THREAD_KEY]
        end

        def with(thread)
          previous = current
          ::Thread.current[THREAD_KEY] = scope_for(thread)
          yield
        ensure
          ::Thread.current[THREAD_KEY] = previous
        end

        def scope_for(value)
          return if value.nil?
          return value.transform_keys(&:to_sym) if value.is_a?(Hash)

          {
            adapter_name: value.adapter.name.to_sym,
            channel_id: value.respond_to?(:channel_id) ? value.channel_id.to_s : value.id.to_s,
            thread_id: value.is_a?(ChatSDK::Thread) ? value.id.to_s : nil
          }
        end
      end
    end
  end
end
