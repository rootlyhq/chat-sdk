# frozen_string_literal: true

module ChatSDK
  class Thread
    include Adapter::Invocation

    attr_reader :id, :channel_id, :adapter, :chat, :current_message

    def initialize(id:, channel_id:, adapter:, chat:, current_message: nil)
      @id = id
      @channel_id = channel_id
      @adapter = adapter
      @chat = chat
      @current_message = current_message
    end

    def subscribe
      chat.state.subscribe(state_key)
    end

    def unsubscribe
      chat.state.unsubscribe(state_key)
    end

    def subscribed?
      chat.state.subscribed?(state_key)
    end

    def post(content)
      return handle_stream(content.stream, content.to_stream_options) if content.is_a?(StreamingPlan)

      message = PostableMessage.from(content)
      adapter.post_message(channel_id: channel_id, message: message, thread_id: id)
    end

    def reply(target, content)
      target_id = target.is_a?(ChatSDK::Message) ? target.id : target.to_s
      if target.is_a?(ChatSDK::Message) && target.thread_id != id
        raise ArgumentError, "cannot reply to a message from another thread"
      end

      message = PostableMessage.from(content)
      adapter.reply_message(channel_id: channel_id, thread_id: id, message_id: target_id, message: message)
    end

    def mark_as_read(message = nil)
      target = message
      target ||= current_message
      raise ArgumentError, "a message or message ID is required" unless target
      if target.is_a?(ChatSDK::Message) && target.thread_id != id
        raise ArgumentError, "cannot mark a message from another thread as read"
      end

      message_id = target.is_a?(ChatSDK::Message) ? target.id : target.to_s
      adapter.mark_as_read(channel_id: channel_id, thread_id: id, message_id: message_id, message: target.is_a?(ChatSDK::Message) ? target : nil)
    end

    def start_typing
      adapter.start_typing(channel_id: channel_id, thread_id: id, message_id: current_message&.id)
    end

    def post_ephemeral(content, user_id:)
      message = PostableMessage.from(content)
      adapter.post_ephemeral(channel_id: channel_id, user_id: user_id, message: message, thread_id: id)
    end

    def post_stream(source = nil, placeholder: nil, **plan_options, &block)
      raise ArgumentError, "provide either a stream source or a block" if !source.nil? && block
      raise ArgumentError, "a stream source or block is required" if source.nil? && !block

      if block
        source = Enumerator.new do |yielder|
          block.call(Streaming::Writer.new(yielder))
        end
      end

      if source.is_a?(StreamingPlan)
        options = StreamingPlan.new(source.stream, **source.options.merge(plan_options)).to_stream_options
        source = source.stream
      else
        options = StreamingPlan.new(source, **plan_options).to_stream_options
      end

      handle_stream(source, options.merge(placeholder: placeholder))
    end

    def edit(message_id, content)
      message = PostableMessage.from(content)
      call_adapter(:edit_message, channel_id: channel_id, message_id: message_id, message: message, thread_id: id)
    end

    def delete(message_id)
      call_adapter(:delete_message, channel_id: channel_id, message_id: message_id, thread_id: id)
    end

    def react(message_id, emoji)
      call_adapter(:add_reaction, channel_id: channel_id, message_id: message_id, emoji: emoji, thread_id: id)
    end

    def unreact(message_id, emoji)
      call_adapter(:remove_reaction, channel_id: channel_id, message_id: message_id, emoji: emoji, thread_id: id)
    end

    def post_ai_stream(enumerable, placeholder: "Thinking...", **plan_options)
      ChatSDK::AI::StreamHandler.stream_to_thread(self, enumerable, placeholder: placeholder, **plan_options)
    end

    def upload(io:, filename:, comment: nil)
      adapter.upload_file(channel_id: channel_id, io: io, filename: filename, thread_id: id, comment: comment)
    end

    def messages(cursor: nil, limit: 50)
      adapter.fetch_messages(channel_id: channel_id, thread_id: id, cursor: cursor, limit: limit)
    end

    def state
      chat.state.get(state_key(:state))
    end

    def set_state(value)
      chat.state.set(state_key(:state), value, ttl: 30 * 24 * 3600)
    end

    def mention_user(user_id)
      adapter.mention(user_id)
    end

    def open_modal(trigger_id:, modal:)
      adapter.open_modal(trigger_id: trigger_id, modal: modal)
    end

    def ==(other)
      other.is_a?(ChatSDK::Thread) && id == other.id && channel_id == other.channel_id
    end
    alias_method :eql?, :==

    def hash
      [id, channel_id].hash
    end

    private

    def handle_stream(source, caller_options)
      options = caller_options.merge(
        update_interval: caller_options[:update_interval] || chat.config.streaming_update_interval
      )
      if current_message
        options[:recipient_user_id] = current_message.author&.id
        options[:recipient_team_id] = extract_recipient_team_id(current_message.raw)
      end
      options = options.reject { |_, value| value.nil? }
      normalized_source = Enumerator.new do |yielder|
        source.each do |item|
          chunk = Streaming::Chunk.normalize(item)
          yielder << chunk unless chunk.nil?
        end
      end

      if adapter.respond_to?(:stream)
        native_message = adapter.stream(
          channel_id: channel_id,
          thread_id: id,
          stream: normalized_source,
          options: options
        )
        return native_message if native_message
      end

      text_source = Enumerator.new do |yielder|
        normalized_source.each do |item|
          text = Streaming::Chunk.text_of(item)
          yielder << text if text
        end
      end
      Streaming::Stream.new(
        adapter: adapter,
        channel_id: channel_id,
        thread_id: id,
        placeholder: options[:placeholder],
        update_interval: options[:update_interval],
        ai_generated: options[:ai_generated] || false
      ).run(text_source)
    end

    def extract_recipient_team_id(raw)
      return unless raw.is_a?(Hash)

      team_id = raw[:team_id] || raw["team_id"]
      team = raw[:team] || raw["team"]
      user = raw[:user] || raw["user"]
      team_id ||= team if team.is_a?(String)
      team_id ||= team[:id] || team["id"] if team.is_a?(Hash)
      team_id ||= user[:team_id] || user["team_id"] if user.is_a?(Hash)
      team_id if team_id.is_a?(String) && !team_id.empty?
    end

    def state_key(suffix = nil)
      base = "#{adapter.name}:#{channel_id}:#{id}"
      suffix ? "#{base}:#{suffix}" : base
    end
  end
end
