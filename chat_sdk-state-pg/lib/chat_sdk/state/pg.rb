# frozen_string_literal: true

require "chat_sdk"
require "pg"
require "json"

module ChatSDK
  module State
    class Pg < Base
      def initialize(url: nil, connection: nil, key_prefix: "chat_sdk", auto_migrate: true)
        @conn = connection || PG.connect(url || ENV["DATABASE_URL"] || ENV["POSTGRES_URL"] || "postgresql://localhost/chat_sdk_dev")
        @key_prefix = key_prefix
        ensure_tables if auto_migrate
      end

      attr_reader :conn

      # Subscriptions

      def subscribe(thread_id)
        @conn.exec_params(
          "INSERT INTO chat_sdk_subscriptions (key_prefix, thread_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
          [@key_prefix, thread_id]
        )
      end

      def unsubscribe(thread_id)
        @conn.exec_params(
          "DELETE FROM chat_sdk_subscriptions WHERE key_prefix = $1 AND thread_id = $2",
          [@key_prefix, thread_id]
        )
      end

      def subscribed?(thread_id)
        result = @conn.exec_params(
          "SELECT 1 FROM chat_sdk_subscriptions WHERE key_prefix = $1 AND thread_id = $2",
          [@key_prefix, thread_id]
        )
        result.ntuples > 0
      end

      # Locks

      def acquire_lock(key, owner:, ttl:)
        ttl_seconds = ttl.to_f
        @conn.exec_params(
          "DELETE FROM chat_sdk_locks WHERE key_prefix = $1 AND lock_key = $2 AND expires_at < NOW()",
          [@key_prefix, key]
        )
        result = @conn.exec_params(
          "INSERT INTO chat_sdk_locks (key_prefix, lock_key, owner, expires_at) " \
          "VALUES ($1, $2, $3, NOW() + INTERVAL '#{ttl_seconds} seconds') ON CONFLICT DO NOTHING",
          [@key_prefix, key, owner]
        )
        result.cmd_tuples > 0
      end

      def release_lock(key, owner:)
        result = @conn.exec_params(
          "DELETE FROM chat_sdk_locks WHERE key_prefix = $1 AND lock_key = $2 AND owner = $3",
          [@key_prefix, key, owner]
        )
        result.cmd_tuples > 0
      end

      def force_lock(key, owner:, ttl:)
        ttl_seconds = ttl.to_f
        @conn.exec_params(
          "INSERT INTO chat_sdk_locks (key_prefix, lock_key, owner, expires_at) " \
          "VALUES ($1, $2, $3, NOW() + INTERVAL '#{ttl_seconds} seconds') " \
          "ON CONFLICT (key_prefix, lock_key) DO UPDATE SET owner = EXCLUDED.owner, expires_at = EXCLUDED.expires_at",
          [@key_prefix, key, owner]
        )
        true
      end

      # Key-value store

      def get(key)
        result = @conn.exec_params(
          "SELECT value FROM chat_sdk_cache WHERE key_prefix = $1 AND cache_key = $2 AND (expires_at IS NULL OR expires_at > NOW())",
          [@key_prefix, key]
        )
        if result.ntuples > 0
          JSON.parse(result[0]["value"])
        else
          # Clean up expired entry if it exists
          @conn.exec_params(
            "DELETE FROM chat_sdk_cache WHERE key_prefix = $1 AND cache_key = $2 AND expires_at IS NOT NULL AND expires_at <= NOW()",
            [@key_prefix, key]
          )
          nil
        end
      end

      def set(key, value, ttl: nil)
        serialized = JSON.generate(value)
        if ttl
          ttl_seconds = ttl.to_f
          @conn.exec_params(
            "INSERT INTO chat_sdk_cache (key_prefix, cache_key, value, expires_at) " \
            "VALUES ($1, $2, $3::jsonb, NOW() + INTERVAL '#{ttl_seconds} seconds') " \
            "ON CONFLICT (key_prefix, cache_key) DO UPDATE SET value = EXCLUDED.value, expires_at = EXCLUDED.expires_at",
            [@key_prefix, key, serialized]
          )
        else
          @conn.exec_params(
            "INSERT INTO chat_sdk_cache (key_prefix, cache_key, value, expires_at) " \
            "VALUES ($1, $2, $3::jsonb, NULL) " \
            "ON CONFLICT (key_prefix, cache_key) DO UPDATE SET value = EXCLUDED.value, expires_at = EXCLUDED.expires_at",
            [@key_prefix, key, serialized]
          )
        end
        value
      end

      def delete(key)
        @conn.exec_params(
          "DELETE FROM chat_sdk_cache WHERE key_prefix = $1 AND cache_key = $2",
          [@key_prefix, key]
        )
        @conn.exec_params(
          "DELETE FROM chat_sdk_locks WHERE key_prefix = $1 AND lock_key = $2",
          [@key_prefix, key]
        )
      end

      def set_if_absent(key, value, ttl: nil)
        serialized = JSON.generate(value)
        # First delete expired entry
        @conn.exec_params(
          "DELETE FROM chat_sdk_cache WHERE key_prefix = $1 AND cache_key = $2 AND expires_at IS NOT NULL AND expires_at < NOW()",
          [@key_prefix, key]
        )
        result = if ttl
          ttl_seconds = ttl.to_f
          @conn.exec_params(
            "INSERT INTO chat_sdk_cache (key_prefix, cache_key, value, expires_at) " \
            "VALUES ($1, $2, $3::jsonb, NOW() + INTERVAL '#{ttl_seconds} seconds') ON CONFLICT DO NOTHING",
            [@key_prefix, key, serialized]
          )
        else
          @conn.exec_params(
            "INSERT INTO chat_sdk_cache (key_prefix, cache_key, value, expires_at) " \
            "VALUES ($1, $2, $3::jsonb, NULL) ON CONFLICT DO NOTHING",
            [@key_prefix, key, serialized]
          )
        end
        result.cmd_tuples > 0
      end

      # Cleanup

      def clear
        @conn.exec_params("DELETE FROM chat_sdk_subscriptions WHERE key_prefix = $1", [@key_prefix])
        @conn.exec_params("DELETE FROM chat_sdk_locks WHERE key_prefix = $1", [@key_prefix])
        @conn.exec_params("DELETE FROM chat_sdk_cache WHERE key_prefix = $1", [@key_prefix])
      end

      def cleanup_expired
        @conn.exec_params(
          "DELETE FROM chat_sdk_cache WHERE key_prefix = $1 AND expires_at IS NOT NULL AND expires_at < NOW()",
          [@key_prefix]
        )
        @conn.exec_params(
          "DELETE FROM chat_sdk_locks WHERE key_prefix = $1 AND expires_at < NOW()",
          [@key_prefix]
        )
      end

      private

      def ensure_tables
        @conn.exec(<<~SQL)
          CREATE TABLE IF NOT EXISTS chat_sdk_subscriptions (
            key_prefix VARCHAR(255) NOT NULL,
            thread_id VARCHAR(512) NOT NULL,
            created_at TIMESTAMP DEFAULT NOW(),
            PRIMARY KEY (key_prefix, thread_id)
          );

          CREATE TABLE IF NOT EXISTS chat_sdk_locks (
            key_prefix VARCHAR(255) NOT NULL,
            lock_key VARCHAR(512) NOT NULL,
            owner VARCHAR(255) NOT NULL,
            expires_at TIMESTAMP NOT NULL,
            PRIMARY KEY (key_prefix, lock_key)
          );

          CREATE TABLE IF NOT EXISTS chat_sdk_cache (
            key_prefix VARCHAR(255) NOT NULL,
            cache_key VARCHAR(512) NOT NULL,
            value JSONB NOT NULL,
            expires_at TIMESTAMP,
            PRIMARY KEY (key_prefix, cache_key)
          );
        SQL
      end
    end
  end
end
