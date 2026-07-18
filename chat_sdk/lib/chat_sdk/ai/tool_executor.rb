# frozen_string_literal: true

module ChatSDK
  module AI
    class ToolExecutor
      def initialize(chat:)
        @chat = chat
      end

      def execute(tool_name, arguments)
        tool_name = tool_name.to_sym
        raise ChatSDK::Error, "Unknown tool: #{tool_name}" unless ToolBuilder::TOOL_DEFINITIONS.key?(tool_name)

        args = arguments.transform_keys(&:to_sym)
        adapter_name = args[:adapter_name].to_sym

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
        thread = @chat.channel(args[:channel_id], adapter_name: adapter_name).thread(args[:channel_id])
        thread.edit(args[:message_id], args[:text])
        {success: true}
      end

      def execute_delete_message(adapter_name, args)
        thread = @chat.channel(args[:channel_id], adapter_name: adapter_name).thread(args[:channel_id])
        thread.delete(args[:message_id])
        {success: true}
      end

      def execute_add_reaction(adapter_name, args)
        thread = @chat.channel(args[:channel_id], adapter_name: adapter_name).thread(args[:channel_id])
        thread.react(args[:message_id], args[:emoji])
        {success: true}
      end

      def execute_remove_reaction(adapter_name, args)
        thread = @chat.channel(args[:channel_id], adapter_name: adapter_name).thread(args[:channel_id])
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
    end
  end
end
