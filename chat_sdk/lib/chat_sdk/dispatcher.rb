# frozen_string_literal: true

require "securerandom"
require "time"

module ChatSDK
  class Dispatcher
    LockHeartbeat = Struct.new(:thread, :mutex, :condition, :stop, :ownership_lost) do
      def ownership_lost?
        mutex.synchronize { ownership_lost }
      end
    end

    def initialize(chat:, config:, state:, registry:)
      @chat = chat
      @config = config
      @state = state
      @registry = registry
      @slot_mutex = Mutex.new
      @slot_condition = ConditionVariable.new
      @active_slots = Hash.new(0)
    end

    def dispatch(event, adapter:, adapter_name:)
      ChatSDK::Instrumentation.instrument("dispatch.chat_sdk", adapter: adapter_name, event_type: event.type) do
        if %i[message_updated message_deleted].include?(event.type)
          return execute_event(event, build_thread(event, adapter))
        end

        return unless dedupe(event, adapter_name)

        thread = build_thread(event, adapter)
        thread_key = thread_key_for(event, adapter_name)
        strategy = @config.concurrency[:strategy]

        if strategy == :concurrent
          return with_concurrent_slot(thread_key) { execute_event(event, thread) }
        end

        owner = "#{Process.pid}:#{::Thread.current.object_id}:#{SecureRandom.uuid}"
        if %i[queue burst debounce].include?(strategy)
          dispatch_queued(event, adapter, thread_key, owner, strategy)
        else
          dispatch_locked(event, thread, thread_key, owner, strategy)
        end
      end
    end

    private

    def dispatch_locked(event, thread, thread_key, owner, strategy)
      acquired = acquire_lock(thread_key, event, owner, force: strategy == :force)
      return unless acquired

      heartbeat = start_lock_heartbeat(thread_key, owner)
      execute_event(event, thread)
    ensure
      stop_lock_heartbeat(heartbeat)
      release_lock(thread_key, owner) if acquired
    end

    def dispatch_queued(event, adapter, thread_key, owner, strategy)
      queue_key = "chat_sdk:queue:#{thread_key}"
      acquired = acquire_lock(thread_key, event, owner, apply_conflict_policy: false)
      pre_enqueued = false

      unless acquired
        enqueue(queue_key, event)
        pre_enqueued = true
        acquired = acquire_lock(thread_key, event, owner, apply_conflict_policy: false)
        return unless acquired
      end

      heartbeat = start_lock_heartbeat(thread_key, owner)
      if strategy == :queue
        execute_event(event, build_thread(event, adapter)) unless pre_enqueued
      else
        enqueue(queue_key, event) unless pre_enqueued
        sleep(@config.concurrency[:debounce].to_f) if strategy == :burst
      end

      if strategy == :debounce
        debounce_loop(queue_key, adapter, heartbeat)
      else
        drain_loop(queue_key, adapter, strategy, heartbeat)
      end
    ensure
      stop_lock_heartbeat(heartbeat)
      release_lock(thread_key, owner) if acquired
    end

    def drain_loop(queue_key, adapter, strategy, heartbeat)
      loop do
        break if heartbeat&.ownership_lost?

        entries = fresh_entries(@state.drain_queue(queue_key))
        break if entries.empty?

        events = entries.map { |entry| EventSerializer.load(entry.fetch("event")) }
        current = events.last
        skipped = if strategy == :debounce
          []
        else
          events[0...-1].filter_map { |queued| queued.message if queued.respond_to?(:message) }
        end
        context = {skipped: skipped, total_since_last_handler: skipped.length + 1}
        execute_event(current, build_thread(current, adapter), context: context)
        ::Thread.pass
      end
    end

    def debounce_loop(queue_key, adapter, heartbeat)
      skipped = []
      loop do
        sleep(@config.concurrency[:debounce].to_f)
        break if heartbeat&.ownership_lost?

        entries = fresh_entries(@state.drain_queue(queue_key))
        break if entries.empty?

        events = entries.map { |entry| EventSerializer.load(entry.fetch("event")) }
        latest = events.last
        skipped.concat(events[0...-1].filter_map { |queued| queued.message if queued.respond_to?(:message) })

        if @state.queue_depth(queue_key).positive?
          skipped << latest.message if latest.respond_to?(:message)
          next
        end

        relevant = skipped.select do |message|
          message.thread_id == latest.thread_id
        end
        context = {skipped: relevant, total_since_last_handler: relevant.length + 1}
        execute_event(latest, build_thread(latest, adapter), context: context)
        skipped.clear
      end
    end

    def enqueue(queue_key, event)
      entry = {"event" => EventSerializer.dump(event), "enqueued_at" => Time.now.iso8601}
      @state.enqueue(
        queue_key,
        entry,
        max_size: @config.concurrency[:max_queue_size],
        drop: @config.concurrency[:on_queue_full]
      )
    end

    def fresh_entries(entries)
      cutoff = Time.now - @config.concurrency[:queue_entry_ttl].to_f
      entries.select do |entry|
        Time.iso8601(entry.fetch("enqueued_at")) >= cutoff
      rescue ArgumentError, KeyError
        false
      end
    end

    def dedupe(event, adapter_name)
      event_id = extract_event_id(event)
      return true unless event_id

      is_new = @state.set_if_absent(
        "chat_sdk:dedupe:#{adapter_name}:#{event_id}",
        true,
        ttl: @config.dedupe_ttl
      )
      ChatSDK::Instrumentation.instrument("dedupe.chat_sdk", adapter: adapter_name, event_id: event_id, duplicate: !is_new)
      is_new
    end

    def extract_event_id(event)
      if event.respond_to?(:message) && event.message
        event.message.id
      elsif event.respond_to?(:message_id) && event.message_id
        "#{event.type}:#{event.message_id}:#{event.timestamp.to_f}"
      elsif event.respond_to?(:raw) && event.raw.is_a?(Hash)
        event.raw[:event_id] || event.raw["event_id"]
      end
    end

    def thread_key_for(event, adapter_name)
      channel_id = event.respond_to?(:channel_id) ? event.channel_id : nil
      thread_id = event.respond_to?(:thread_id) ? event.thread_id : nil
      lock_scope = @config.concurrency[:lock_scope]
      scope_id = (lock_scope&.to_sym == :channel) ? channel_id : thread_id
      "#{adapter_name}:#{channel_id}:#{scope_id}"
    end

    def acquire_lock(thread_key, event, owner, force: false, apply_conflict_policy: true)
      lock_key = "chat_sdk:lock:#{thread_key}"
      acquired = @state.acquire_lock(lock_key, owner: owner, ttl: @config.concurrency[:lock_ttl])

      if !acquired && apply_conflict_policy
        policy = force ? :force : @config.on_lock_conflict
        policy = policy.call(thread_key, event) if policy.respond_to?(:call)
        if policy == :force
          @state.force_lock(lock_key, owner: owner, ttl: @config.concurrency[:lock_ttl])
          acquired = true
        end
      end

      ChatSDK::Instrumentation.instrument("lock.chat_sdk", key: thread_key, acquired: acquired)
      acquired
    end

    def release_lock(thread_key, owner)
      @state.release_lock("chat_sdk:lock:#{thread_key}", owner: owner)
    end

    def start_lock_heartbeat(thread_key, owner)
      lock_ttl = @config.concurrency[:lock_ttl].to_f
      max_lifetime = @config.concurrency[:max_lock_lifetime].to_f
      mutex = Mutex.new
      condition = ConditionVariable.new
      heartbeat = LockHeartbeat.new(mutex: mutex, condition: condition, stop: false, ownership_lost: false)
      heartbeat.thread = ::Thread.new do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        interval = [lock_ttl / 3.0, 0.01].max
        loop do
          should_stop = mutex.synchronize do
            condition.wait(mutex, interval) unless heartbeat.stop
            heartbeat.stop
          end
          break if should_stop
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started >= max_lifetime

          extended = @state.extend_lock("chat_sdk:lock:#{thread_key}", owner: owner, ttl: lock_ttl)
          unless extended
            mutex.synchronize { heartbeat.ownership_lost = true }
            break
          end
        rescue NotImplementedError
          break
        end
      end
      heartbeat
    end

    def stop_lock_heartbeat(heartbeat)
      return unless heartbeat

      heartbeat.mutex.synchronize do
        heartbeat.stop = true
        heartbeat.condition.signal
      end
      heartbeat.thread.join
    end

    def build_thread(event, adapter)
      thread_id = event.respond_to?(:thread_id) ? event.thread_id : nil
      channel_id = event.respond_to?(:channel_id) ? event.channel_id : nil
      return nil unless thread_id && channel_id

      current_message = event.respond_to?(:message) ? event.message : nil
      ChatSDK::Thread.new(id: thread_id, channel_id: channel_id, adapter: adapter, chat: @chat, current_message: current_message)
    end

    def execute_event(event, thread, context: nil)
      @registry.handlers_for(event).each do |handler|
        execute_handler(handler, event, thread, context: context)
      end
    end

    def execute_handler(handler, event, thread, context: nil)
      ChatSDK::Instrumentation.instrument("handler.chat_sdk", handler_type: event.type) do
        case event.type
        when :mention, :subscribed_message, :direct_message
          handler.block.call(thread, event.message, context)
        when :message_updated
          handler.block.call(thread, event.message, event.previous_message)
        when :reaction, :action, :slash_command, :message_deleted
          add_thread_to_event(event, thread)
          handler.block.call(event)
        end
      end
    rescue => e
      ChatSDK::Log.error("Handler error (#{event.type}): #{e.message}")
      ChatSDK::Log.debug(e.backtrace&.first(5)&.join("\n"))
    end

    def add_thread_to_event(event, thread)
      event.thread = thread if event.respond_to?(:thread=)
    end

    def with_concurrent_slot(key)
      max = @config.concurrency[:max_concurrent]
      return yield unless max

      @slot_mutex.synchronize do
        @slot_condition.wait(@slot_mutex) while @active_slots[key] >= max
        @active_slots[key] += 1
      end
      yield
    ensure
      if max
        @slot_mutex.synchronize do
          @active_slots[key] -= 1
          @slot_condition.broadcast
        end
      end
    end
  end
end
