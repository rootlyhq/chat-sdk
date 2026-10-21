# frozen_string_literal: true

require "chat_sdk"
require "mysql2"
require "json"
require "uri"

module ChatSDK
  module State
    class Mysql < Base
      def self.parse_url(url)
        uri = URI.parse(url)
        options = {}
        options[:host] = uri.host if uri.host
        options[:port] = uri.port if uri.port
        options[:username] = URI::DEFAULT_PARSER.unescape(uri.user) if uri.user
        options[:password] = URI::DEFAULT_PARSER.unescape(uri.password) if uri.password
        database = uri.path.delete_prefix("/")
        options[:database] = URI::DEFAULT_PARSER.unescape(database) unless database.empty?
        options.merge!(URI.decode_www_form(uri.query.to_s).to_h.transform_keys(&:to_sym))
        options
      end

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
          "DELETE FROM chat_sdk_locks WHERE key_prefix = ? AND lock_key = ? AND expires_at < NOW(6)"
        )
        del_stmt.execute(@key_prefix, key)
        ins_stmt = @conn.prepare(
          "INSERT IGNORE INTO chat_sdk_locks (key_prefix, lock_key, owner, expires_at) " \
          "VALUES (?, ?, ?, DATE_ADD(NOW(6), INTERVAL #{ttl_seconds} SECOND))"
        )
        ins_stmt.execute(@key_prefix, key, owner)
        ins_stmt.affected_rows > 0
      end

      def release_lock(key, owner:)
        stmt = @conn.prepare(
          "DELETE FROM chat_sdk_locks WHERE key_prefix = ? AND lock_key = ? AND owner = ?"
        )
        stmt.execute(@key_prefix, key, owner)
        stmt.affected_rows > 0
      end

      def force_lock(key, owner:, ttl:)
        ttl_seconds = ttl.to_f
        stmt = @conn.prepare(
          "INSERT INTO chat_sdk_locks (key_prefix, lock_key, owner, expires_at) " \
          "VALUES (?, ?, ?, DATE_ADD(NOW(6), INTERVAL #{ttl_seconds} SECOND)) " \
          "ON DUPLICATE KEY UPDATE owner = VALUES(owner), expires_at = VALUES(expires_at)"
        )
        stmt.execute(@key_prefix, key, owner)
        true
      end

      def extend_lock(key, owner:, ttl:)
        stmt = @conn.prepare(
          "UPDATE chat_sdk_locks SET expires_at = DATE_ADD(NOW(6), INTERVAL #{ttl.to_f} SECOND) " \
          "WHERE key_prefix = ? AND lock_key = ? AND owner = ? AND expires_at > NOW(6)"
        )
        stmt.execute(@key_prefix, key, owner)
        stmt.affected_rows > 0
      end

      # Key-value store

      def get(key)
        stmt = @conn.prepare(
          "SELECT value FROM chat_sdk_cache WHERE key_prefix = ? AND cache_key = ? AND (expires_at IS NULL OR expires_at > NOW(6))"
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
            "VALUES (?, ?, ?, DATE_ADD(NOW(6), INTERVAL #{ttl.to_f} SECOND)) " \
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
          "DELETE FROM chat_sdk_cache WHERE key_prefix = ? AND cache_key = ? AND expires_at IS NOT NULL AND expires_at < NOW(6)"
        )
        del_stmt.execute(@key_prefix, key)
        stmt = if ttl
          @conn.prepare(
            "INSERT IGNORE INTO chat_sdk_cache (key_prefix, cache_key, value, expires_at) " \
            "VALUES (?, ?, ?, DATE_ADD(NOW(6), INTERVAL #{ttl.to_f} SECOND))"
          )
        else
          @conn.prepare(
            "INSERT IGNORE INTO chat_sdk_cache (key_prefix, cache_key, value, expires_at) " \
            "VALUES (?, ?, ?, NULL)"
          )
        end
        stmt.execute(@key_prefix, key, serialized)
        stmt.affected_rows > 0
      end

      def enqueue(key, value, max_size:, drop: :drop_oldest)
        @conn.query("START TRANSACTION")
        count_stmt = @conn.prepare(
          "SELECT id FROM chat_sdk_queues WHERE key_prefix = ? AND queue_key = ? ORDER BY id FOR UPDATE"
        )
        ids = count_stmt.execute(@key_prefix, key).map { |row| row["id"] }
        if ids.length >= max_size && drop.to_sym == :drop_newest
          @conn.query("COMMIT")
          return ids.length
        end

        insert = @conn.prepare("INSERT INTO chat_sdk_queues (key_prefix, queue_key, value) VALUES (?, ?, ?)")
        insert.execute(@key_prefix, key, JSON.generate(value))
        overflow = ids.length + 1 - max_size
        if overflow.positive?
          placeholders = Array.new(overflow, "?").join(", ")
          remove = @conn.prepare("DELETE FROM chat_sdk_queues WHERE id IN (#{placeholders})")
          remove.execute(*ids.first(overflow))
        end
        @conn.query("COMMIT")
        [ids.length + 1, max_size].min
      rescue
        @conn.query("ROLLBACK")
        raise
      end

      def drain_queue(key)
        @conn.query("START TRANSACTION")
        select = @conn.prepare(
          "SELECT id, value FROM chat_sdk_queues WHERE key_prefix = ? AND queue_key = ? ORDER BY id FOR UPDATE"
        )
        rows = select.execute(@key_prefix, key).to_a
        delete = @conn.prepare("DELETE FROM chat_sdk_queues WHERE key_prefix = ? AND queue_key = ?")
        delete.execute(@key_prefix, key)
        @conn.query("COMMIT")
        rows.map { |row| JSON.parse(row["value"]) }
      rescue
        @conn.query("ROLLBACK")
        raise
      end

      def queue_depth(key)
        stmt = @conn.prepare("SELECT COUNT(*) AS count FROM chat_sdk_queues WHERE key_prefix = ? AND queue_key = ?")
        stmt.execute(@key_prefix, key).first["count"].to_i
      end

      # Cleanup

      def clear
        s1 = @conn.prepare("DELETE FROM chat_sdk_subscriptions WHERE key_prefix = ?")
        s1.execute(@key_prefix)
        s2 = @conn.prepare("DELETE FROM chat_sdk_locks WHERE key_prefix = ?")
        s2.execute(@key_prefix)
        s3 = @conn.prepare("DELETE FROM chat_sdk_cache WHERE key_prefix = ?")
        s3.execute(@key_prefix)
        s4 = @conn.prepare("DELETE FROM chat_sdk_queues WHERE key_prefix = ?")
        s4.execute(@key_prefix)
      end

      def cleanup_expired
        s1 = @conn.prepare(
          "DELETE FROM chat_sdk_cache WHERE key_prefix = ? AND expires_at IS NOT NULL AND expires_at < NOW(6)"
        )
        s1.execute(@key_prefix)
        s2 = @conn.prepare(
          "DELETE FROM chat_sdk_locks WHERE key_prefix = ? AND expires_at < NOW(6)"
        )
        s2.execute(@key_prefix)
      end

      private

      def connect(url)
        Mysql2::Client.new(self.class.parse_url(url))
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
            expires_at TIMESTAMP(6) NOT NULL,
            PRIMARY KEY (key_prefix, lock_key)
          ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        SQL
        @conn.query(<<~SQL)
          CREATE TABLE IF NOT EXISTS chat_sdk_cache (
            key_prefix VARCHAR(255) NOT NULL,
            cache_key VARCHAR(512) NOT NULL,
            value JSON NOT NULL,
            expires_at TIMESTAMP(6) NULL DEFAULT NULL,
            PRIMARY KEY (key_prefix, cache_key)
          ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        SQL
        @conn.query(<<~SQL)
          CREATE TABLE IF NOT EXISTS chat_sdk_queues (
            id BIGINT NOT NULL AUTO_INCREMENT,
            key_prefix VARCHAR(255) NOT NULL,
            queue_key VARCHAR(512) NOT NULL,
            value JSON NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            INDEX chat_sdk_queues_lookup (key_prefix, queue_key)
          ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        SQL
        ensure_expiration_precision
      end

      def ensure_expiration_precision
        columns = @conn.query(<<~SQL).each_with_object({}) do |row, result|
          SELECT TABLE_NAME, DATETIME_PRECISION
          FROM information_schema.columns
          WHERE table_schema = DATABASE()
            AND table_name IN ('chat_sdk_locks', 'chat_sdk_cache')
            AND column_name = 'expires_at'
        SQL
          result[row["TABLE_NAME"]] = row["DATETIME_PRECISION"].to_i
        end

        definitions = {
          "chat_sdk_locks" => "TIMESTAMP(6) NOT NULL",
          "chat_sdk_cache" => "TIMESTAMP(6) NULL DEFAULT NULL"
        }
        definitions.each do |table_name, definition|
          next if columns[table_name] == 6

          @conn.query("ALTER TABLE #{table_name} MODIFY expires_at #{definition}")
        end
      end
    end
  end
end
