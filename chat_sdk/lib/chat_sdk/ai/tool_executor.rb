# frozen_string_literal: true

module ChatSDK
  module AI
    class ToolExecutor
      def initialize(chat:, scope: nil, strict_scope: false)
        @chat = chat
        @scope = if scope == false
          false
        else
          ConversationScope.scope_for(scope)
        end
        validate_scope!(@scope) if @scope
        @strict_scope = strict_scope
        @warned_unscoped = {}
      end

      def execute(tool_name, arguments)
        tool_name = tool_name.to_sym
        raise ChatSDK::Error, "Unknown tool: #{tool_name}" unless ToolBuilder::TOOL_DEFINITIONS.key?(tool_name)

        args = arguments.transform_keys(&:to_sym)
        adapter_name = args[:adapter_name].to_sym
        guard_scope!(tool_name, adapter_name, args)

        send(:"execute_#{tool_name}", adapter_name, args)
      end

      private

      def execute_fetch_messages(adapter_name, args)
        channel = @chat.channel(args[:channel_id], adapter_name: adapter_name)
        messages, _cursor = channel.adapter.fetch_messages(
          channel_id: args[:channel_id],
          thread_id: args[:thread_id],
          limit: args[:limit] || 20
        )
        serialize_messages(messages)
      end

      def execute_fetch_thread(adapter_name, args)
        channel = @chat.channel(args[:channel_id], adapter_name: adapter_name)
        messages, _cursor = channel.adapter.fetch_messages(
          channel_id: args[:channel_id],
          thread_id: args[:thread_id]
        )
        serialize_messages(messages)
      end

      def execute_post_message(adapter_name, args)
        channel = @chat.channel(args[:channel_id], adapter_name: adapter_name)
        message = ChatSDK::PostableMessage.new(text: args[:text], ai_generated: true)
        if args[:thread_id]
          thread = channel.thread(args[:thread_id])
          result = thread.post(message)
        else
          result = channel.post(message)
        end
        {id: result.id, text: args[:text]}
      end

      def execute_send_direct_message(adapter_name, args)
        dm_channel = @chat.open_dm(args[:user_id], adapter_name: adapter_name)
        result = dm_channel.post(ChatSDK::PostableMessage.new(text: args[:text], ai_generated: true))
        {id: result.id, channel_id: dm_channel.id}
      end

      def execute_edit_message(adapter_name, args)
        thread = target_thread(adapter_name, args)
        thread.edit(args[:message_id], ChatSDK::PostableMessage.new(text: args[:text], ai_generated: true))
        {success: true}
      end

      def execute_delete_message(adapter_name, args)
        thread = target_thread(adapter_name, args)
        thread.delete(args[:message_id])
        {success: true}
      end

      def execute_add_reaction(adapter_name, args)
        thread = target_thread(adapter_name, args)
        thread.react(args[:message_id], args[:emoji])
        {success: true}
      end

      def execute_remove_reaction(adapter_name, args)
        thread = target_thread(adapter_name, args)
        thread.unreact(args[:message_id], args[:emoji])
        {success: true}
      end

      def execute_start_typing(adapter_name, args)
        adapter = @chat.adapter(adapter_name)
        scoped_message_id = @scope.is_a?(Hash) ? @scope[:message_id] : nil
        message_id = args[:message_id] || ConversationScope.current&.[](:message_id) || scoped_message_id
        adapter.start_typing(channel_id: args[:channel_id], thread_id: args[:thread_id], message_id: message_id)
        {success: true}
      end

      def serialize_messages(messages)
        messages.map { |m| {id: m.id, text: m.text, author: m.author&.name, timestamp: m.timestamp} }
      end

      def target_thread(adapter_name, args)
        channel = @chat.channel(args[:channel_id], adapter_name: adapter_name)
        channel.thread(args[:thread_id] || args[:channel_id])
      end

      def guard_scope!(tool_name, adapter_name, args)
        return if @scope == false

        scope = @scope || ConversationScope.current
        unless scope
          raise ChatSDK::Error, "AI tool call requires an explicit scope when run inside a handler without a conversation" if ConversationScope.active?

          unless @warned_unscoped[tool_name]
            ChatSDK::Log.warn("AI tool ran without a conversation scope; pass scope: to create_executor to confine access")
            @warned_unscoped[tool_name] = true
          end

          return
        end

        return if tool_name == :send_direct_message

        target_channel = args[:channel_id].to_s
        target_thread = args[:thread_id]&.to_s
        same_channel = adapter_name == scope.fetch(:adapter_name).to_sym && target_channel == scope.fetch(:channel_id).to_s
        scope_is_channel = scope[:thread_id].nil?
        in_scope = same_channel && (!@strict_scope || scope_is_channel || target_thread == scope[:thread_id].to_s)
        return if in_scope

        target = [adapter_name, target_channel, target_thread].compact.join(":")
        active = [scope[:adapter_name], scope[:channel_id], scope[:thread_id]].compact.join(":")
        raise ChatSDK::Error, "AI tool call blocked: executor is scoped to #{active.inspect}, but targeted #{target.inspect}"
      end

      def validate_scope!(scope)
        %i[channel_id thread_id].each do |key|
          next if key == :thread_id && scope[key].nil?
          next unless scope.key?(key) && scope[key].to_s.empty?

          raise ChatSDK::ConfigurationError, "AI tool scope #{key} must not be empty"
        end
      end
    end
  end
end
