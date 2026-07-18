# frozen_string_literal: true

module ChatSDK
  module State
    class Memory < Base
      def initialize
        @mutex = Mutex.new
        @store = {}
        @expirations = {}
        @subscriptions = Set.new
        @locks = {}
      end

      def subscribe(thread_id)
        @mutex.synchronize { @subscriptions.add(thread_id) }
      end

      def unsubscribe(thread_id)
        @mutex.synchronize { @subscriptions.delete(thread_id) }
      end

      def subscribed?(thread_id)
        @mutex.synchronize { @subscriptions.include?(thread_id) }
      end

      def acquire_lock(key, owner:, ttl:)
        @mutex.synchronize do
          expire_if_needed(key)
          return false if @locks.key?(key)
          @locks[key] = {owner: owner, expires_at: Time.now.to_f + ttl}
          true
        end
      end

      def release_lock(key, owner:)
        @mutex.synchronize do
          return false unless @locks[key] && @locks[key][:owner] == owner
          @locks.delete(key)
          true
        end
      end

      def force_lock(key, owner:, ttl:)
        @mutex.synchronize do
          @locks[key] = {owner: owner, expires_at: Time.now.to_f + ttl}
          true
        end
      end

      def get(key)
        @mutex.synchronize do
          expire_if_needed(key)
          @store[key]
        end
      end

      def set(key, value, ttl: nil)
        @mutex.synchronize do
          @store[key] = value
          @expirations[key] = Time.now.to_f + ttl if ttl
          value
        end
      end

      def delete(key)
        @mutex.synchronize do
          @store.delete(key)
          @expirations.delete(key)
          @locks.delete(key)
        end
      end

      def set_if_absent(key, value, ttl: nil)
        @mutex.synchronize do
          expire_if_needed(key)
          return false if @store.key?(key)
          @store[key] = value
          @expirations[key] = Time.now.to_f + ttl if ttl
          true
        end
      end

      def clear
        @mutex.synchronize do
          @store.clear
          @expirations.clear
          @subscriptions.clear
          @locks.clear
        end
      end

      private

      def expire_if_needed(key)
        if @expirations[key] && @expirations[key] < Time.now.to_f
          @store.delete(key)
          @expirations.delete(key)
        end
        if @locks[key] && @locks[key][:expires_at] < Time.now.to_f
          @locks.delete(key)
        end
      end
    end
  end
end
