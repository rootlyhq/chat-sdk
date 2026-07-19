# frozen_string_literal: true

require "chat_sdk"
require "mysql2"
require "json"

module ChatSDK
  module State
    class Mysql < Base
      def initialize(url: nil, connection: nil, key_prefix: "chat_sdk", auto_migrate: true)
        @conn = connection || connect(url || ENV["MYSQL_URL"] || ENV["DATABASE_URL"] || "mysql2://root@localhost/chat_sdk_dev")
        @key_prefix = key_prefix
        ensure_tables if auto_migrate
      end

      attr_reader :conn

      # Subscriptions

      def subscribe(thread_id)
        stmt = @conn.prepare(
          "INSERT IGNORE INTO chat_sdk_subscriptions (key_prefix, thread_id) VALUES (?, ?)"
        )
        stmt.execute(@key_prefix, thread_id)
      end

      def unsubscribe(thread_id)
        stmt = @conn.prepare(
          "DELETE FROM chat_sdk_subscriptions WHERE key_prefix = ? AND thread_id = ?"
        )
        stmt.execute(@key_prefix, thread_id)
      end

      def subscribed?(thread_id)
        stmt = @conn.prepare(
          "SELECT 1 FROM chat_sdk_subscriptions WHERE key_prefix = ? AND thread_id = ?"
        )
        result = stmt.execute(@key_prefix, thread_id)
        result.count > 0
      end

      # Locks

      def acquire_lock(key, owner:, ttl:)
        ttl_seconds = ttl.to_f
        del_stmt = @conn.prepare(
          "DELETE FROM chat_sdk_locks WHERE key_prefix = ? AND lock_key = ? AND expires_at < NOW()"
        )
        del_stmt.execute(@key_prefix, key)
        ins_stmt = @conn.prepare(
          "INSERT IGNORE INTO chat_sdk_locks (key_prefix, lock_key, owner, expires_at) " \
          "VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL #{ttl_seconds} SECOND))"
        )
        ins_stmt.execute(@key_prefix, key, owner)
        @conn.affected_rows > 0
      end

      def release_lock(key, owner:)
        stmt = @conn.prepare(
          "DELETE FROM chat_sdk_locks WHERE key_prefix = ? AND lock_key = ? AND owner = ?"
        )
        stmt.execute(@key_prefix, key, owner)
        @conn.affected_rows > 0
      end

      def force_lock(key, owner:, ttl:)
        ttl_seconds = ttl.to_f
        stmt = @conn.prepare(
          "INSERT INTO chat_sdk_locks (key_prefix, lock_key, owner, expires_at) " \
          "VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL #{ttl_seconds} SECOND)) " \
          "ON DUPLICATE KEY UPDATE owner = VALUES(owner), expires_at = VALUES(expires_at)"
        )
        stmt.execute(@key_prefix, key, owner)
        true
      end

      # Key-value store

      def get(key)
        stmt = @conn.prepare(
          "SELECT value FROM chat_sdk_cache WHERE key_prefix = ? AND cache_key = ? AND (expires_at IS NULL OR expires_at > NOW())"
        )
        result = stmt.execute(@key_prefix, key)
        row = result.first
        return JSON.parse(row["value"]) if row

        nil
      end

      def set(key, value, ttl: nil)
        serialized = JSON.generate(value)
        stmt = if ttl
          @conn.prepare(
            "INSERT INTO chat_sdk_cache (key_prefix, cache_key, value, expires_at) " \
            "VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL #{ttl.to_f} SECOND)) " \
            "ON DUPLICATE KEY UPDATE value = VALUES(value), expires_at = VALUES(expires_at)"
          )
        else
          @conn.prepare(
            "INSERT INTO chat_sdk_cache (key_prefix, cache_key, value, expires_at) " \
            "VALUES (?, ?, ?, NULL) " \
            "ON DUPLICATE KEY UPDATE value = VALUES(value), expires_at = VALUES(expires_at)"
          )
        end
        stmt.execute(@key_prefix, key, serialized)
        value
      end

      def delete(key)
        stmt1 = @conn.prepare(
          "DELETE FROM chat_sdk_cache WHERE key_prefix = ? AND cache_key = ?"
        )
        stmt1.execute(@key_prefix, key)
        stmt2 = @conn.prepare(
          "DELETE FROM chat_sdk_locks WHERE key_prefix = ? AND lock_key = ?"
        )
        stmt2.execute(@key_prefix, key)
      end

      def set_if_absent(key, value, ttl: nil)
        serialized = JSON.generate(value)
        del_stmt = @conn.prepare(
          "DELETE FROM chat_sdk_cache WHERE key_prefix = ? AND cache_key = ? AND expires_at IS NOT NULL AND expires_at < NOW()"
        )
        del_stmt.execute(@key_prefix, key)
        stmt = if ttl
          @conn.prepare(
            "INSERT IGNORE INTO chat_sdk_cache (key_prefix, cache_key, value, expires_at) " \
            "VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL #{ttl.to_f} SECOND))"
          )
        else
          @conn.prepare(
            "INSERT IGNORE INTO chat_sdk_cache (key_prefix, cache_key, value, expires_at) " \
            "VALUES (?, ?, ?, NULL)"
          )
        end
        stmt.execute(@key_prefix, key, serialized)
        @conn.affected_rows > 0
      end

      # Cleanup

      def clear
        s1 = @conn.prepare("DELETE FROM chat_sdk_subscriptions WHERE key_prefix = ?")
        s1.execute(@key_prefix)
        s2 = @conn.prepare("DELETE FROM chat_sdk_locks WHERE key_prefix = ?")
        s2.execute(@key_prefix)
        s3 = @conn.prepare("DELETE FROM chat_sdk_cache WHERE key_prefix = ?")
        s3.execute(@key_prefix)
      end

      def cleanup_expired
        s1 = @conn.prepare(
          "DELETE FROM chat_sdk_cache WHERE key_prefix = ? AND expires_at IS NOT NULL AND expires_at < NOW()"
        )
        s1.execute(@key_prefix)
        s2 = @conn.prepare(
          "DELETE FROM chat_sdk_locks WHERE key_prefix = ? AND expires_at < NOW()"
        )
        s2.execute(@key_prefix)
      end

      private

      def connect(url)
        Mysql2::Client.new(url)
      end

      def ensure_tables
        @conn.query(<<~SQL)
          CREATE TABLE IF NOT EXISTS chat_sdk_subscriptions (
            key_prefix VARCHAR(255) NOT NULL,
            thread_id VARCHAR(512) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (key_prefix, thread_id)
          ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        SQL
        @conn.query(<<~SQL)
          CREATE TABLE IF NOT EXISTS chat_sdk_locks (
            key_prefix VARCHAR(255) NOT NULL,
            lock_key VARCHAR(512) NOT NULL,
            owner VARCHAR(255) NOT NULL,
            expires_at TIMESTAMP NOT NULL,
            PRIMARY KEY (key_prefix, lock_key)
          ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        SQL
        @conn.query(<<~SQL)
          CREATE TABLE IF NOT EXISTS chat_sdk_cache (
            key_prefix VARCHAR(255) NOT NULL,
            cache_key VARCHAR(512) NOT NULL,
            value JSON NOT NULL,
            expires_at TIMESTAMP NULL DEFAULT NULL,
            PRIMARY KEY (key_prefix, cache_key)
          ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        SQL
      end
    end
  end
end
