module ChatSDK
  class Dispatcher
    def initialize(chat:, config:, state:, registry:)
      @chat = chat
      @config = config
      @state = state
      @registry = registry
    end

    def dispatch(event, adapter:, adapter_name:)
      return unless dedupe(event, adapter_name)

      thread = build_thread(event, adapter)
      thread_key = thread_key_for(event, adapter_name)

      return unless acquire_lock(thread_key, event)

      begin
        handlers = @registry.handlers_for(event)
        handlers.each { |handler| execute_handler(handler, event, thread) }
      ensure
        release_lock(thread_key)
      end
    end

    private

    def dedupe(event, adapter_name)
      event_id = extract_event_id(event)
      return true unless event_id

      @state.set_if_absent(
        "chat_sdk:dedupe:#{adapter_name}:#{event_id}",
        true,
        ttl: @config.dedupe_ttl
      )
    end

    def extract_event_id(event)
      if event.respond_to?(:message) && event.message
        event.message.id
      elsif event.respond_to?(:raw) && event.raw.is_a?(Hash)
        event.raw[:event_id] || event.raw["event_id"]
      else
        nil
      end
    end

    def thread_key_for(event, adapter_name)
      channel_id = event.respond_to?(:channel_id) ? event.channel_id : nil
      thread_id = event.respond_to?(:thread_id) ? event.thread_id : nil
      "#{adapter_name}:#{channel_id}:#{thread_id}"
    end

    def lock_owner
      @lock_owner ||= "#{Process.pid}:#{::Thread.current.object_id}"
    end

    def acquire_lock(thread_key, event)
      lock_key = "chat_sdk:lock:#{thread_key}"
      return true if @state.acquire_lock(lock_key, owner: lock_owner, ttl: 30)

      case @config.on_lock_conflict
      when :drop
        ChatSDK::Log.debug("Lock conflict, dropping event for #{thread_key}")
        false
      when :force
        @state.force_lock(lock_key, owner: lock_owner, ttl: 30)
        true
      else
        if @config.on_lock_conflict.respond_to?(:call)
          policy = @config.on_lock_conflict.call(thread_key, event)
          case policy
          when :force
            @state.force_lock(lock_key, owner: lock_owner, ttl: 30)
            true
          else
            false
          end
        else
          false
        end
      end
    end

    def release_lock(thread_key)
      @state.release_lock("chat_sdk:lock:#{thread_key}", owner: lock_owner)
    end

    def build_thread(event, adapter)
      thread_id = event.respond_to?(:thread_id) ? event.thread_id : nil
      channel_id = event.respond_to?(:channel_id) ? event.channel_id : nil
      return nil unless thread_id && channel_id

      ChatSDK::Thread.new(id: thread_id, channel_id: channel_id, adapter: adapter, chat: @chat)
    end

    def execute_handler(handler, event, thread)
      case event.type
      when :mention, :subscribed_message, :direct_message
        handler.block.call(thread, event.message)
      when :reaction, :action, :slash_command
        add_thread_to_event(event, thread)
        handler.block.call(event)
      end
    rescue => e
      ChatSDK::Log.error("Handler error (#{event.type}): #{e.message}")
      ChatSDK::Log.debug(e.backtrace&.first(5)&.join("\n"))
    end

    def add_thread_to_event(event, thread)
      event.instance_variable_set(:@thread, thread)
      unless event.respond_to?(:thread)
        event.define_singleton_method(:thread) { @thread }
      end
    end
  end
end
