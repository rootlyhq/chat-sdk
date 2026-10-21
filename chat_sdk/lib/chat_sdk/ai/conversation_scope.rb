# frozen_string_literal: true

module ChatSDK
  module AI
    module ConversationScope
      THREAD_KEY = :chat_sdk_ai_conversation_scope
      ACTIVE_KEY = :chat_sdk_ai_conversation_scope_active

      class << self
        def current
          ::Thread.current[THREAD_KEY]
        end

        def active?
          !!::Thread.current[ACTIVE_KEY]
        end

        def with(thread)
          previous = current
          previous_active = active?
          ::Thread.current[THREAD_KEY] = scope_for(thread)
          ::Thread.current[ACTIVE_KEY] = true
          yield
        ensure
          ::Thread.current[THREAD_KEY] = previous
          ::Thread.current[ACTIVE_KEY] = previous_active
        end

        def scope_for(value)
          return if value.nil?
          return value.transform_keys(&:to_sym) if value.is_a?(Hash)

          scope = {
            adapter_name: value.adapter.name.to_sym,
            channel_id: value.respond_to?(:channel_id) ? value.channel_id.to_s : value.id.to_s,
            thread_id: value.is_a?(ChatSDK::Thread) ? value.id.to_s : nil
          }
          scope[:message_id] = value.current_message.id if value.respond_to?(:current_message) && value.current_message
          scope
        end
      end
    end
  end
end
