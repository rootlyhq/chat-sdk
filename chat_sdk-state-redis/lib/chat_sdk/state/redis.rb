# frozen_string_literal: true

require "chat_sdk"
require "redis-client"

module ChatSDK
  module State
    class Redis < Base
      LOCK_RELEASE_SCRIPT = <<~LUA
        if redis.call("GET", KEYS[1]) == ARGV[1] then
          return redis.call("DEL", KEYS[1])
        else
          return 0
        end
      LUA

      def initialize(url: nil, client: nil)
        @client = client || RedisClient.config(url: url || ENV["REDIS_URL"] || "redis://localhost:6379").new_client
      end

      attr_reader :client

      # Subscriptions
      def subscribe(thread_id)
        @client.call("SADD", subscription_key, thread_id)
      end

      def unsubscribe(thread_id)
        @client.call("SREM", subscription_key, thread_id)
      end

      def subscribed?(thread_id)
        @client.call("SISMEMBER", subscription_key, thread_id) == 1
      end

      # Locks
      def acquire_lock(key, owner:, ttl:)
        result = @client.call("SET", lock_key(key), owner, "NX", "PX", (ttl * 1000).to_i)
        result == "OK"
      end

      def release_lock(key, owner:)
        result = @client.call("EVAL", LOCK_RELEASE_SCRIPT, 1, lock_key(key), owner)
        result == 1
      end

      def force_lock(key, owner:, ttl:)
        @client.call("SET", lock_key(key), owner, "PX", (ttl * 1000).to_i)
        true
      end

      # Key-value store
      def get(key)
        value = @client.call("GET", kv_key(key))
        value ? JSON.parse(value) : nil
      end

      def set(key, value, ttl: nil)
        serialized = JSON.generate(value)
        if ttl
          @client.call("SET", kv_key(key), serialized, "PX", (ttl * 1000).to_i)
        else
          @client.call("SET", kv_key(key), serialized)
        end
        value
      end

      def delete(key)
        @client.call("DEL", kv_key(key), lock_key(key))
      end

      def set_if_absent(key, value, ttl: nil)
        serialized = JSON.generate(value)
        result = if ttl
          @client.call("SET", kv_key(key), serialized, "NX", "PX", (ttl * 1000).to_i)
        else
          @client.call("SET", kv_key(key), serialized, "NX")
        end
        result == "OK"
      end

      def clear
        keys = @client.call("KEYS", "chat_sdk:*")
        @client.call("DEL", *keys) if keys.any?
      end

      private

      def subscription_key
        "chat_sdk:subscriptions"
      end

      def lock_key(key)
        "chat_sdk:lock:#{key}"
      end

      def kv_key(key)
        "chat_sdk:kv:#{key}"
      end
    end
  end
end
