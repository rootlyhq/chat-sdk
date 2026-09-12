# frozen_string_literal: true

require "time"

module ChatSDK
  class History
    attr_reader :user, :thread, :channel

    def initialize(chat)
      @user = UserHistory.new(chat)
      @thread = ThreadHistory.new(chat)
      @channel = ChannelHistory.new(chat)
    end

    class UserHistory
      def initialize(chat)
        @chat = chat
      end

      def append(thread, message, user_key: nil)
        user_key ||= resolve_user_key(thread, message)
        return nil unless user_key

        entry = normalize_entry(thread, message, user_key)
        entries = Array(@chat.state.get(storage_key(user_key)))
        entries << entry
        max = @chat.config.history_user[:max_per_user]
        entries = entries.last(max) if max && max != false
        @chat.state.set(storage_key(user_key), entries, ttl: @chat.config.history_user[:retention])
        entry
      end

      def list(user_key:, limit: nil, platforms: nil, thread_id: nil, roles: nil)
        entries = Array(@chat.state.get(storage_key(user_key)))
        entries = entries.select { |entry| Array(platforms).map(&:to_s).include?(entry["platform"].to_s) } if platforms
        entries = entries.select { |entry| entry["thread_id"] == thread_id } if thread_id
        entries = entries.select { |entry| Array(roles).map(&:to_s).include?(entry["role"].to_s) } if roles
        limit ? entries.last(limit) : entries
      end

      def delete(user_key:)
        count = Array(@chat.state.get(storage_key(user_key))).length
        @chat.state.delete(storage_key(user_key))
        {deleted: count}
      end

      def to_prompt_entries(entries)
        entries.map { |entry| {role: entry["role"], content: entry["text"]} }
      end

      private

      def resolve_user_key(thread, message)
        resolver = @chat.config.history_user[:identity]
        return resolver.call(thread, message) if resolver
        message.author.email if message.is_a?(Message) && message.author&.email
      rescue => e
        ChatSDK::Log.warn("History identity resolver failed: #{e.message}")
        nil
      end

      def normalize_entry(thread, message, user_key)
        if message.is_a?(Message)
          {
            "id" => message.id,
            "user_key" => user_key,
            "role" => message.author&.bot? ? "assistant" : "user",
            "text" => message.text.to_s,
            "platform" => message.platform.to_s,
            "thread_id" => thread.id,
            "timestamp" => (message.timestamp || Time.now).iso8601
          }
        else
          data = message.transform_keys(&:to_sym)
          {
            "id" => data[:id],
            "user_key" => user_key,
            "role" => (data[:role] || "assistant").to_s,
            "text" => data[:text].to_s,
            "platform" => (data[:platform] || thread.adapter.name).to_s,
            "thread_id" => thread.id,
            "timestamp" => (data[:timestamp] || Time.now).iso8601
          }
        end
      end

      def storage_key(user_key)
        "chat_sdk:history:user:#{user_key}"
      end
    end

    class ThreadHistory
      def initialize(chat)
        @chat = chat
      end

      def list(thread, cursor: nil, limit: 50)
        unless thread.is_a?(ChatSDK::Thread)
          raise ArgumentError, "thread history requires a ChatSDK::Thread"
        end

        messages, next_cursor = thread.adapter.fetch_messages(
          channel_id: thread.channel_id,
          thread_id: thread.id,
          cursor: cursor,
          limit: limit
        )
        {messages: messages, next_cursor: next_cursor}
      end
    end

    class ChannelHistory
      def initialize(chat)
        @chat = chat
      end

      def list_messages(channel, cursor: nil, limit: 50)
        unless channel.is_a?(ChatSDK::Channel)
          raise ArgumentError, "channel history requires a ChatSDK::Channel"
        end

        messages, next_cursor = channel.adapter.fetch_channel_messages(
          channel_id: channel.id,
          cursor: cursor,
          limit: limit
        )
        {messages: messages, next_cursor: next_cursor}
      end

      def list_threads(channel, cursor: nil, limit: 50)
        unless channel.is_a?(ChatSDK::Channel)
          raise ArgumentError, "channel history requires a ChatSDK::Channel"
        end

        threads, next_cursor = channel.adapter.list_threads(
          channel_id: channel.id,
          cursor: cursor,
          limit: limit
        )
        {threads: threads, next_cursor: next_cursor}
      end
    end
  end
end
