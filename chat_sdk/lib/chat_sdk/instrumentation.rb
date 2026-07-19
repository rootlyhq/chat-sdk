# frozen_string_literal: true

module ChatSDK
  module Instrumentation
    @subscribers = Hash.new { |h, k| h[k] = [] }
    @mutex = Mutex.new

    class << self
      def subscribe(event_name, &block)
        @mutex.synchronize { @subscribers[event_name] << block }
        block
      end

      def unsubscribe(event_name, block)
        @mutex.synchronize { @subscribers[event_name].delete(block) }
      end

      def instrument(event_name, payload = {})
        start = monotonic_now
        result = yield if block_given?
        payload[:duration] = monotonic_now - start
        notify(event_name, payload)
        result
      rescue => e
        payload[:duration] = monotonic_now - start
        payload[:error] = e
        notify(event_name, payload)
        raise
      end

      def reset!
        @mutex.synchronize { @subscribers.clear }
      end

      private

      def notify(event_name, payload)
        listeners = @mutex.synchronize { @subscribers[event_name].dup }
        listeners.each { |block| block.call(event_name, payload) }
      rescue => e
        ChatSDK::Log.debug("Instrumentation subscriber error: #{e.message}")
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
