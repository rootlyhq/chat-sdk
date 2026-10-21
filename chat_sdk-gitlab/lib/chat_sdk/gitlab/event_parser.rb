# frozen_string_literal: true

require "time"

module ChatSDK
  module GitLab
    class EventParser
      PROJECT_BOT_USERNAME = /\A(?:project|group)_\d+_bot/
      EMOJI_NAMES = {
        "thumbsup" => "thumbs_up",
        "thumbsdown" => "thumbs_down",
        "face_palm" => "facepalm",
        "hugging" => "hug",
        "first_place" => "medal",
        "pencil" => "memo",
        "e-mail" => "email",
        "cloud_rain" => "rain"
      }.freeze

      def initialize(bot_user_id:, bot_username:, explicit_bot_username:)
        @bot_user_id = bot_user_id
        @bot_username = bot_username
        @explicit_bot_username = explicit_bot_username
      end

      def parse(payload, event_type:)
        case event_type
        when "Note Hook" then parse_note(payload)
        when "Emoji Hook" then parse_emoji(payload)
        else []
        end
      end

      private

      def parse_note(payload)
        attributes = payload["object_attributes"]
        return [] unless payload["object_kind"] == "note" && attributes.is_a?(Hash)
        return [] if attributes["action"] && attributes["action"] != "create"
        return [] if attributes["system"] || attributes["internal"] || attributes["confidential"]
        return [] if attributes["event_type"] == "confidential_note" || payload["event_type"] == "confidential_note"
        return [] if payload.dig("issue", "confidential")

        noteable = resolve_noteable(attributes["noteable_type"], payload)
        return [] unless noteable
        return [] unless numeric?(attributes["id"])

        author_data = payload["user"].is_a?(Hash) ? payload["user"] : {}
        author_id = author_data["id"] || attributes["author_id"]
        return [] if self_user?(author_id, author_data["username"])

        project_id = payload["project_id"] || payload.dig("project", "id") || attributes["project_id"]
        return [] unless numeric?(project_id) && numeric?(noteable[:iid])

        thread_id = encode_thread_id(
          project_id,
          noteable[:type],
          noteable[:iid],
          attributes["discussion_id"]
        )
        channel_id = "gitlab:#{project_id}"
        text = attributes["note"].to_s
        timestamp = parse_timestamp(attributes["created_at"])
        author = parse_author(author_data, author_id)
        message = ChatSDK::Message.new(
          id: attributes["id"].to_s,
          text: text,
          author: author,
          thread_id: thread_id,
          channel_id: channel_id,
          platform: :gitlab,
          raw: payload,
          timestamp: timestamp,
          is_mention: mentions_bot?(text)
        )

        [ChatSDK::Events::Mention.new(
          message: message,
          thread_id: thread_id,
          channel_id: channel_id,
          platform: :gitlab,
          adapter_name: :gitlab,
          raw: payload,
          timestamp: timestamp
        )]
      end

      def parse_emoji(payload)
        attributes = payload["object_attributes"]
        note = payload["note"]
        return [] unless payload["object_kind"] == "emoji" && attributes.is_a?(Hash)
        return [] unless attributes["awardable_type"] == "Note" && note.is_a?(Hash)
        return [] if note["system"] || note["internal"] || note["confidential"]
        return [] if payload.dig("issue", "confidential")
        return [] unless %w[award revoke].include?(payload["event_type"])

        noteable = resolve_noteable(note["noteable_type"], payload)
        return [] unless noteable

        user = payload["user"].is_a?(Hash) ? payload["user"] : {}
        user_id = attributes["user_id"] || user["id"]
        return [] if self_user?(user_id, user["username"])

        project_id = payload["project_id"] || payload.dig("project", "id")
        return [] unless numeric?(project_id) && numeric?(noteable[:iid]) && numeric?(note["id"])

        thread_id = encode_thread_id(project_id, noteable[:type], noteable[:iid], note["discussion_id"])
        channel_id = "gitlab:#{project_id}"
        emoji_name = attributes["name"].to_s

        [ChatSDK::Events::Reaction.new(
          emoji: EMOJI_NAMES.fetch(emoji_name, emoji_name),
          user_id: user_id.to_s,
          message_id: note["id"].to_s,
          thread_id: thread_id,
          channel_id: channel_id,
          added: payload["event_type"] == "award",
          platform: :gitlab,
          adapter_name: :gitlab,
          raw: payload,
          timestamp: parse_timestamp(attributes["created_at"])
        )]
      end

      def resolve_noteable(type, payload)
        case type
        when "MergeRequest"
          iid = payload.dig("merge_request", "iid")
          {type: :merge_request, iid: iid} if iid
        when "Issue"
          iid = payload.dig("issue", "iid")
          {type: :issue, iid: iid} if iid
        end
      end

      def encode_thread_id(project_id, noteable_type, noteable_iid, discussion_id)
        kind = (noteable_type == :merge_request) ? "mr" : "issue"
        thread_id = "gitlab:#{project_id}:#{kind}:#{noteable_iid}"
        discussion_id ? "#{thread_id}:#{discussion_id}" : thread_id
      end

      def parse_author(user, user_id)
        username = user["username"].to_s
        ChatSDK::Author.new(
          id: user_id.to_s,
          name: user["name"] || username,
          platform: :gitlab,
          bot: !!(
            user["bot"] == true || PROJECT_BOT_USERNAME.match?(username) ||
              (@bot_user_id && user_id.to_s == @bot_user_id)
          )
        )
      end

      def self_user?(user_id, username)
        return user_id.to_s == @bot_user_id if @bot_user_id

        @explicit_bot_username && username.to_s.casecmp?(@bot_username)
      end

      def mentions_bot?(text)
        masked = ChatSDK::Format::Mentions.mask_code_spans(text)
        username = Regexp.escape(@bot_username.to_s.sub(/\A@/, ""))
        masked.match?(/(?<!\w)@#{username}(?![\w-])/i)
      end

      def numeric?(value)
        value.to_s.match?(/\A\d+\z/)
      end

      def parse_timestamp(value)
        return unless value

        Time.parse(value)
      rescue ArgumentError
        nil
      end
    end
  end
end
