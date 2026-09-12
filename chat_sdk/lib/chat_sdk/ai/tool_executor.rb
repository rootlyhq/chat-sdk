# frozen_string_literal: true

module ChatSDK
  module AI
    class ToolExecutor
      def initialize(chat:, scope: nil, strict_scope: false)
        @chat = chat
        @scope = if scope == false
          false
        else
          ConversationScope.scope_for(scope) || ConversationScope.current&.dup
        end
        @strict_scope = strict_scope
        @warned_unscoped = false
      end

      def execute(tool_name, arguments)
        tool_name = tool_name.to_sym
        raise ChatSDK::Error, "Unknown tool: #{tool_name}" unless ToolBuilder::TOOL_DEFINITIONS.key?(tool_name)

        args = arguments.transform_keys(&:to_sym)
        adapter_name = args[:adapter_name].to_sym
        guard_scope!(adapter_name, args) unless tool_name == :send_direct_message

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
        if args[:thread_id]
          thread = channel.thread(args[:thread_id])
          result = thread.post(args[:text])
        else
          result = channel.post(args[:text])
        end
        {id: result.id, text: args[:text]}
      end

      def execute_send_direct_message(adapter_name, args)
        dm_channel = @chat.open_dm(args[:user_id], adapter_name: adapter_name)
        result = dm_channel.post(args[:text])
        {id: result.id, channel_id: dm_channel.id}
      end

      def execute_edit_message(adapter_name, args)
        thread = target_thread(adapter_name, args)
        thread.edit(args[:message_id], args[:text])
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
        adapter.start_typing(channel_id: args[:channel_id], thread_id: args[:thread_id])
        {success: true}
      end

      def serialize_messages(messages)
        messages.map { |m| {id: m.id, text: m.text, author: m.author&.name, timestamp: m.timestamp} }
      end

      def target_thread(adapter_name, args)
        channel = @chat.channel(args[:channel_id], adapter_name: adapter_name)
        channel.thread(args[:thread_id] || args[:channel_id])
      end

      def guard_scope!(adapter_name, args)
        return if @scope == false

        scope = @scope || ConversationScope.current
        unless scope
          unless @warned_unscoped
            ChatSDK::Log.warn("AI tool ran without a conversation scope; pass scope: to create_executor to confine access")
            @warned_unscoped = true
          end
          return
        end

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
    end
  end
end
