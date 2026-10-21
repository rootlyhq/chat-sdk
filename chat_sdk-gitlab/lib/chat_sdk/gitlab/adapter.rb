# frozen_string_literal: true

require "base64"
require "digest"
require "openssl"
require "rack/utils"

module ChatSDK
  module GitLab
    class Adapter < ChatSDK::Adapter::Base
      capabilities :edit_messages, :delete_messages, :reactions, :typing_indicator, :message_history

      DEFAULT_API_URL = "https://gitlab.com/api/v4"
      DEFAULT_BOT_USERNAME = "gitlab-bot"
      MAX_PER_PAGE = 100
      SIGNATURE_TOLERANCE = 5 * 60
      THREAD_ID_PATTERN = /\Agitlab:(\d+):(mr|issue):(\d+)(?::([0-9a-f]+))?\z/
      CHANNEL_ID_PATTERN = /\Agitlab:(\d+)\z/
      NOTE_ID_PATTERN = /\A\d+\z/
      PAGE_PATTERN = /\A[1-9]\d*\z/
      SIGNING_TOKEN_PATTERN = /\A(?:whsec_)?([A-Za-z0-9+\/]{43}=)\z/
      GITLAB_EMOJI_NAMES = {
        "thumbs_up" => "thumbsup",
        "thumbs_down" => "thumbsdown",
        "facepalm" => "face_palm",
        "thinking" => "thinking",
        "hug" => "hugging",
        "medal" => "first_place",
        "memo" => "pencil",
        "email" => "e-mail",
        "rain" => "cloud_rain"
      }.freeze
      NORMALIZED_EMOJI_NAMES = GITLAB_EMOJI_NAMES.invert.freeze

      attr_reader :client, :bot_user_id, :bot_username

      def initialize(token: nil, webhook_signing_token: nil, webhook_secret: nil,
        api_url: nil, bot_user_id: nil, bot_username: nil)
        @token = token || ENV["GITLAB_TOKEN"]
        @webhook_signing_token = webhook_signing_token || ENV["GITLAB_WEBHOOK_SIGNING_TOKEN"]
        @webhook_secret = webhook_secret || ENV["GITLAB_WEBHOOK_SECRET"]
        @api_url = api_url || ENV["GITLAB_API_URL"] || DEFAULT_API_URL
        @bot_user_id = bot_user_id || ENV["GITLAB_BOT_USER_ID"]
        configured_username = bot_username || ENV["GITLAB_BOT_USERNAME"]
        @explicit_bot_username = !configured_username.nil? && !configured_username.empty?
        @bot_username = configured_username || DEFAULT_BOT_USERNAME

        raise ChatSDK::ConfigurationError, "GitLab token required; set GITLAB_TOKEN" if blank?(@token)
        if blank?(@webhook_signing_token) && blank?(@webhook_secret)
          raise ChatSDK::ConfigurationError,
            "GitLab webhook verification required; set GITLAB_WEBHOOK_SIGNING_TOKEN or GITLAB_WEBHOOK_SECRET"
        end

        @bot_user_id = @bot_user_id.to_s unless blank?(@bot_user_id)
        @identity_resolved = @bot_user_id && @explicit_bot_username
        @signing_key = decode_signing_token(@webhook_signing_token) unless blank?(@webhook_signing_token)
        @client = ApiClient.new(token: @token, api_url: @api_url)
        @format_converter = FormatConverter.new
        @card_renderer = CardRenderer.new
      end

      def name
        :gitlab
      end

      def verify_request!(rack_request)
        body = rack_request.body.read
        rack_request.body.rewind
        signature = rack_request.get_header("HTTP_WEBHOOK_SIGNATURE")

        if @signing_key && signature
          return true if verify_signature(
            body,
            rack_request.get_header("HTTP_WEBHOOK_ID"),
            rack_request.get_header("HTTP_WEBHOOK_TIMESTAMP"),
            signature
          )

          raise ChatSDK::SignatureVerificationError, "Invalid GitLab webhook signature"
        end

        token = rack_request.get_header("HTTP_X_GITLAB_TOKEN")
        if @webhook_secret && token && secure_token_match?(@webhook_secret, token)
          return true
        end

        raise ChatSDK::SignatureVerificationError, "Invalid GitLab webhook token or signature"
      end

      def ack_response(_rack_request)
        nil
      end

      def parse_events(rack_request)
        payload = read_json_body(rack_request)
        return [] unless payload.is_a?(Hash)

        event_type = rack_request.get_header("HTTP_X_GITLAB_EVENT")
        expected_kind = {"Note Hook" => "note", "Emoji Hook" => "emoji"}[event_type]
        return [] unless expected_kind && payload["object_kind"] == expected_kind
        return [] unless resolve_bot_identity

        EventParser.new(
          bot_user_id: @bot_user_id,
          bot_username: @bot_username,
          explicit_bot_username: @explicit_bot_username
        ).parse(payload, event_type: event_type)
      rescue JSON::ParserError
        []
      end

      def encode_thread_id(project_id:, noteable_type:, noteable_iid:, discussion_id: nil)
        project = project_id.to_s
        iid = noteable_iid.to_s
        kind = case noteable_type.to_s
        when "mr", "merge_request", "MergeRequest" then "mr"
        when "issue", "Issue" then "issue"
        else raise ArgumentError, "Invalid GitLab noteable type: #{noteable_type}"
        end
        unless project.match?(/\A\d+\z/) && iid.match?(/\A\d+\z/)
          raise ArgumentError, "GitLab project and noteable IDs must be numeric"
        end
        if discussion_id && !discussion_id.to_s.match?(/\A[0-9a-f]+\z/)
          raise ArgumentError, "Invalid GitLab discussion ID: #{discussion_id}"
        end

        id = "gitlab:#{project}:#{kind}:#{iid}"
        discussion_id ? "#{id}:#{discussion_id}" : id
      end

      def decode_thread_id(thread_id)
        match = THREAD_ID_PATTERN.match(thread_id.to_s)
        raise ArgumentError, "Invalid GitLab thread ID: #{thread_id}" unless match

        {
          project_id: match[1].to_i,
          noteable_type: match[2] == "mr" ? :merge_request : :issue,
          noteable_iid: match[3].to_i,
          discussion_id: match[4]
        }
      end

      def channel_id_from_thread_id(thread_id)
        "gitlab:#{decode_thread_id(thread_id)[:project_id]}"
      end

      def post_message(channel_id:, message:, thread_id: nil)
        thread = validated_thread!(channel_id, thread_id)
        note = @client.request_api(
          :post,
          note_collection_path(thread),
          body: {"body" => render(message)}
        )
        @bot_user_id ||= note.dig("author", "id").to_s if note.dig("author", "id")
        build_message(note, thread, channel_id, thread_id)
      end

      def edit_message(channel_id:, message_id:, message:, thread_id: nil)
        thread = validated_thread!(channel_id, thread_id)
        validate_message_id!(message_id)
        validate_discussion_note!(thread, message_id)
        note = @client.request_api(
          :put,
          "#{noteable_path(thread)}/notes/#{message_id}",
          body: {"body" => render(message)}
        )
        build_message(note, thread, channel_id, thread_id)
      end

      def delete_message(channel_id:, message_id:, thread_id: nil)
        thread = validated_thread!(channel_id, thread_id)
        validate_message_id!(message_id)
        validate_discussion_note!(thread, message_id)
        @client.request_api(:delete, "#{noteable_path(thread)}/notes/#{message_id}")
      end

      def add_reaction(channel_id:, message_id:, emoji:, thread_id: nil)
        thread = validated_thread!(channel_id, thread_id)
        validate_message_id!(message_id)
        validate_discussion_note!(thread, message_id)
        award_path = "#{noteable_path(thread)}/notes/#{message_id}/award_emoji"
        name = to_gitlab_emoji(emoji)

        begin
          @client.request_api(:post, award_path, body: {"name" => name})
        rescue ChatSDK::PlatformError => error
          raise unless error.status == 404 && @bot_user_id
          raise unless @client.request_all(award_path).any? do |award|
            award["name"] == name && award.dig("user", "id").to_s == @bot_user_id
          end
        end
      end

      def remove_reaction(channel_id:, message_id:, emoji:, thread_id: nil)
        thread = validated_thread!(channel_id, thread_id)
        validate_message_id!(message_id)
        validate_discussion_note!(thread, message_id)
        resolve_bot_identity unless @bot_user_id
        raise ChatSDK::ConfigurationError, "GitLab bot user ID is required to remove reactions" unless @bot_user_id

        award_path = "#{noteable_path(thread)}/notes/#{message_id}/award_emoji"
        award = @client.request_all(award_path).find do |item|
          item["name"] == to_gitlab_emoji(emoji) &&
            item.dig("user", "id").to_s == @bot_user_id
        end
        return unless award && NOTE_ID_PATTERN.match?(award["id"].to_s)

        @client.request_api(:delete, "#{award_path}/#{award["id"]}")
      end

      def fetch_messages(channel_id:, thread_id: nil, cursor: nil, limit: 50)
        thread = validated_thread!(channel_id, thread_id)
        per_page = [[limit.to_i, 1].max, MAX_PER_PAGE].min

        if thread[:discussion_id]
          discussion = @client.request_api(
            :get,
            "#{noteable_path(thread)}/discussions/#{thread[:discussion_id]}"
          )
          notes = Array(discussion["notes"]).reject { |note| internal_note?(note) }
          notes.sort_by! { |note| parse_timestamp(note["created_at"]) || Time.at(0) }
          messages = notes.map { |note| build_message(note, thread, channel_id, thread_id) }
          return [messages.last(per_page), nil]
        end

        page = PAGE_PATTERN.match?(cursor.to_s) ? cursor.to_s : "1"
        notes, next_page = @client.request_page(
          "#{noteable_path(thread)}/notes",
          query: {
            order_by: "created_at",
            sort: "desc",
            per_page: per_page,
            page: page
          }
        )
        notes = notes.is_a?(Array) ? notes.reverse : []
        messages = notes.reject { |note| internal_note?(note) }
          .map { |note| build_message(note, thread, channel_id, thread_id) }
        [messages, next_page.to_s.empty? ? nil : next_page]
      end

      def start_typing(channel_id:, thread_id: nil, message_id: nil)
        validated_thread!(channel_id, thread_id)
        nil
      end

      def mention(user)
        "@#{user.to_s.sub(/\A@/, "")}"
      end

      def render(postable_message)
        message = ChatSDK::PostableMessage.from(postable_message)
        return @card_renderer.render(message.card) if message.card?

        @format_converter.from_markdown(message.text)
      end

      private

      def resolve_bot_identity
        return true if @identity_resolved

        user = @client.current_user
        @bot_user_id ||= user["id"].to_s if user["id"]
        if !@explicit_bot_username && user["username"]
          @bot_username = user["username"]
        end
        @identity_resolved = !blank?(@bot_user_id) &&
          (@explicit_bot_username || !blank?(user["username"]))
        @bot_user_id || @explicit_bot_username
      rescue ChatSDK::PlatformError, Faraday::Error
        @bot_user_id || @explicit_bot_username
      end

      def verify_signature(body, message_id, timestamp, signature)
        return false if blank?(message_id) || blank?(timestamp)
        return false unless timestamp.to_s.match?(/\A\d+\z/)
        return false if (Time.now.to_i - timestamp.to_i).abs > SIGNATURE_TOLERANCE

        digest = OpenSSL::HMAC.digest("SHA256", @signing_key, "#{message_id}.#{timestamp}.#{body}")
        expected = "v1,#{Base64.strict_encode64(digest)}"
        signature.split(/\s+/).any? do |candidate|
          candidate.start_with?("v1,") &&
            candidate.bytesize == expected.bytesize &&
            Rack::Utils.secure_compare(candidate, expected)
        end
      end

      def secure_token_match?(expected, received)
        expected_digest = Digest::SHA256.hexdigest(expected)
        received_digest = Digest::SHA256.hexdigest(received)
        Rack::Utils.secure_compare(expected_digest, received_digest)
      end

      def decode_signing_token(token)
        match = SIGNING_TOKEN_PATTERN.match(token.to_s)
        raise ChatSDK::ConfigurationError, "Invalid GitLab webhook signing token" unless match

        Base64.strict_decode64(match[1])
      rescue ArgumentError
        raise ChatSDK::ConfigurationError, "Invalid GitLab webhook signing token"
      end

      def validated_thread!(channel_id, thread_id)
        thread = decode_thread_id(thread_id)
        channel_project = decode_channel_id(channel_id)
        unless channel_project == thread[:project_id]
          raise ArgumentError, "GitLab thread #{thread_id} does not belong to channel #{channel_id}"
        end

        thread
      end

      def decode_channel_id(channel_id)
        match = CHANNEL_ID_PATTERN.match(channel_id.to_s)
        raise ArgumentError, "Invalid GitLab channel ID: #{channel_id}" unless match

        match[1].to_i
      end

      def validate_message_id!(message_id)
        raise ArgumentError, "Invalid GitLab note ID: #{message_id}" unless NOTE_ID_PATTERN.match?(message_id.to_s)
      end

      def validate_discussion_note!(thread, message_id)
        discussion_id = thread[:discussion_id]
        return unless discussion_id

        discussion = @client.request_api(
          :get,
          "#{noteable_path(thread)}/discussions/#{discussion_id}"
        )
        return if Array(discussion["notes"]).any? { |note| note["id"].to_s == message_id.to_s }

        raise ArgumentError, "GitLab note #{message_id} does not belong to discussion #{discussion_id}"
      end

      def noteable_path(thread)
        collection = thread[:noteable_type] == :merge_request ? "merge_requests" : "issues"
        "/projects/#{thread[:project_id]}/#{collection}/#{thread[:noteable_iid]}"
      end

      def note_collection_path(thread)
        base = noteable_path(thread)
        discussion_id = thread[:discussion_id]
        discussion_id ? "#{base}/discussions/#{discussion_id}/notes" : "#{base}/notes"
      end

      def build_message(note, thread, channel_id, thread_id)
        author = note["author"].is_a?(Hash) ? note["author"] : {}
        author_id = author["id"] || "bot"
        author_name = author["name"] || author["username"] || "GitLab bot"
        author_username = author["username"].to_s
        text = @format_converter.to_markdown(note["body"] || "")
        ChatSDK::Message.new(
          id: note["id"].to_s,
          text: text,
          author: ChatSDK::Author.new(
            id: author_id.to_s,
            name: author_name,
            platform: :gitlab,
            bot: author["bot"] == true ||
              EventParser::PROJECT_BOT_USERNAME.match?(author_username) ||
              (@bot_user_id && author_id.to_s == @bot_user_id) ||
              author_username.casecmp?(@bot_username)
          ),
          thread_id: thread_id,
          channel_id: channel_id,
          platform: :gitlab,
          raw: {
            note: note,
            project_id: thread[:project_id],
            noteable_type: thread[:noteable_type],
            noteable_iid: thread[:noteable_iid],
            discussion_id: thread[:discussion_id]
          },
          timestamp: parse_timestamp(note["created_at"]),
          is_mention: mention_in?(text)
        )
      end

      def mention_in?(text)
        masked = ChatSDK::Format::Mentions.mask_code_spans(text)
        username = Regexp.escape(@bot_username.to_s.sub(/\A@/, ""))
        masked.match?(/(?<!\w)@#{username}(?![\w-])/i)
      end

      def internal_note?(note)
        note["system"] == true || note["internal"] == true || note["confidential"] == true
      end

      def parse_timestamp(value)
        Time.parse(value) if value
      rescue ArgumentError
        nil
      end

      def to_gitlab_emoji(emoji)
        name = emoji.respond_to?(:name) ? emoji.name.to_s : emoji.to_s
        GITLAB_EMOJI_NAMES.fetch(name, name)
      end

      def blank?(value)
        value.nil? || value.to_s.empty?
      end
    end
  end
end
