# frozen_string_literal: true

require "json"
require "time"

module ChatSDK
  class EventSerializer
    class << self
      def dump(event)
        data = common_event(event)
        case event.type
        when :mention, :subscribed_message, :direct_message, :message_updated
          data["message"] = dump_message(event.message)
          data["previous_message"] = dump_message(event.previous_message) if event.respond_to?(:previous_message) && event.previous_message
        when :message_deleted
          data.merge!(
            "message_id" => event.message_id,
            "previous_message" => dump_message(event.previous_message),
            "deleted_at" => event.deleted_at&.iso8601(6)
          )
        when :reaction
          data.merge!("emoji" => event.emoji, "user_id" => event.user_id, "message_id" => event.message_id, "added" => event.added?)
        when :action
          data.merge!("action_id" => event.action_id, "value" => event.value, "values" => json_safe(event.values), "user" => dump_author(event.user), "trigger_id" => event.trigger_id)
        when :slash_command
          data.merge!("command" => event.command, "text" => event.text, "user_id" => event.user_id, "trigger_id" => event.trigger_id)
        when :installed, :uninstalled
          data.merge!(
            "installation_id" => event.installation_id,
            "team_id" => event.team_id,
            "tenant_id" => event.tenant_id,
            "conversation_id" => event.conversation_id,
            "action" => event.action,
            "user" => dump_author(event.user)
          )
        when :assistant_thread_started, :assistant_context_changed
          data.merge!(
            "thread_ts" => event.thread_ts,
            "user_id" => event.user_id,
            "context" => event.context.to_h.transform_keys(&:to_s)
          )
        when :app_home_opened
          data["user_id"] = event.user_id
          data["tab"] = event.tab
        when :member_joined_channel
          data["user_id"] = event.user_id
          data["inviter_id"] = event.inviter_id
        end
        data
      end

      def load(data)
        data = data.transform_keys(&:to_s)
        type = data.fetch("type").to_sym
        common = {
          thread_id: data["thread_id"],
          channel_id: data["channel_id"],
          platform: data["platform"].to_sym,
          adapter_name: data["adapter_name"].to_sym,
          raw: data["raw"],
          timestamp: parse_time(data["timestamp"])
        }
        case type
        when :mention, :subscribed_message, :direct_message
          class_name = {mention: Events::Mention, subscribed_message: Events::SubscribedMessage, direct_message: Events::DirectMessage}.fetch(type)
          class_name.new(message: load_message(data["message"]), **common)
        when :message_updated
          Events::MessageUpdated.new(message: load_message(data["message"]), previous_message: load_message(data["previous_message"]), **common)
        when :message_deleted
          Events::MessageDeleted.new(
            message_id: data["message_id"],
            previous_message: load_message(data["previous_message"]),
            deleted_at: parse_time(data["deleted_at"]),
            **common
          )
        when :reaction
          Events::Reaction.new(emoji: data["emoji"], user_id: data["user_id"], message_id: data["message_id"], added: data["added"], **common)
        when :action
          Events::Action.new(action_id: data["action_id"], value: data["value"], values: data["values"], user: load_author(data["user"]), trigger_id: data["trigger_id"], **common)
        when :slash_command
          common.delete(:thread_id)
          Events::SlashCommand.new(command: data["command"], text: data["text"], user_id: data["user_id"], trigger_id: data["trigger_id"], **common)
        when :installed, :uninstalled
          common.delete(:thread_id)
          common.delete(:channel_id)
          event_class = if type == :installed
            Events::Installed
          else
            Events::Uninstalled
          end
          event_class.new(
            installation_id: data["installation_id"],
            team_id: data["team_id"],
            tenant_id: data["tenant_id"],
            conversation_id: data["conversation_id"],
            action: data["action"],
            user: load_author(data["user"]),
            **common
          )
        when :assistant_thread_started, :assistant_context_changed
          event_class = if type == :assistant_thread_started
            Events::AssistantThreadStarted
          else
            Events::AssistantContextChanged
          end
          event_class.new(
            thread_ts: data["thread_ts"],
            user_id: data["user_id"],
            context: data["context"] || {},
            **common
          )
        when :app_home_opened
          common.delete(:thread_id)
          Events::AppHomeOpened.new(user_id: data["user_id"], tab: data["tab"], **common)
        when :member_joined_channel
          common.delete(:thread_id)
          Events::MemberJoinedChannel.new(user_id: data["user_id"], inviter_id: data["inviter_id"], **common)
        else
          raise ArgumentError, "unsupported queued event type: #{type}"
        end
      end

      private

      def common_event(event)
        {
          "type" => event.type.to_s,
          "platform" => event.platform.to_s,
          "adapter_name" => event.adapter_name.to_s,
          "thread_id" => event.respond_to?(:thread_id) ? event.thread_id : nil,
          "channel_id" => event.respond_to?(:channel_id) ? event.channel_id : nil,
          "raw" => json_safe(event.raw),
          "timestamp" => event.timestamp&.iso8601(6)
        }
      end

      def dump_message(message)
        return unless message

        {
          "id" => message.id,
          "text" => message.text,
          "author" => dump_author(message.author),
          "thread_id" => message.thread_id,
          "channel_id" => message.channel_id,
          "platform" => message.platform.to_s,
          "attachments" => json_safe(message.attachments),
          "links" => json_safe(message.links),
          "reply_to" => dump_message(message.reply_to),
          "subject" => json_safe(message.subject),
          "raw" => json_safe(message.raw),
          "timestamp" => message.timestamp&.iso8601(6),
          "is_mention" => message.is_mention
        }
      end

      def load_message(data)
        return unless data

        data = data.transform_keys(&:to_s)
        Message.new(
          id: data["id"],
          text: data["text"],
          author: load_author(data["author"]),
          thread_id: data["thread_id"],
          channel_id: data["channel_id"],
          platform: data["platform"].to_sym,
          attachments: data["attachments"] || [],
          links: data["links"] || [],
          reply_to: load_message(data["reply_to"]),
          subject: data["subject"],
          raw: data["raw"],
          timestamp: parse_time(data["timestamp"]),
          is_mention: data["is_mention"]
        )
      end

      def dump_author(author)
        return unless author

        {
          "id" => author.id,
          "name" => author.name,
          "platform" => author.platform.to_s,
          "bot" => author.bot?,
          "me" => author.me?,
          "system" => author.system?,
          "locale" => author.locale,
          "email" => author.email,
          "raw" => json_safe(author.raw)
        }
      end

      def load_author(data)
        return unless data

        data = data.transform_keys(&:to_s)
        Author.new(
          id: data["id"],
          name: data["name"],
          platform: data["platform"].to_sym,
          bot: data["bot"],
          me: data["me"],
          system: data["system"],
          locale: data["locale"],
          email: data["email"],
          raw: data["raw"]
        )
      end

      def parse_time(value)
        Time.iso8601(value) if value
      end

      def json_safe(value)
        JSON.parse(JSON.generate(value))
      rescue JSON::GeneratorError, TypeError
        nil
      end
    end
  end
end
