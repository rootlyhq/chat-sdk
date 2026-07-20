# frozen_string_literal: true

module ChatSDK
  module Slack
    class Adapter < ChatSDK::Adapter::Base
      capabilities :edit_messages, :delete_messages, :ephemeral_messages,
        :file_uploads, :reactions, :modals, :typing_indicator,
        :streaming_edit, :threads, :direct_messages, :message_history

      attr_reader :client

      def initialize(bot_token: nil, signing_secret: nil)
        @bot_token = bot_token || ENV["SLACK_BOT_TOKEN"]
        @signing_secret = signing_secret || ENV["SLACK_SIGNING_SECRET"]

        raise ChatSDK::ConfigurationError, "Slack bot_token required" unless @bot_token
        raise ChatSDK::ConfigurationError, "Slack signing_secret required" unless @signing_secret

        ::Slack.configure do |config|
          config.token = @bot_token
        end

        @client = ::Slack::Web::Client.new(token: @bot_token)
        @renderer = BlockKitRenderer.new
        @modal_renderer = ModalRenderer.new
      end

      def name
        :slack
      end

      # Inbound
      def verify_request!(rack_request)
        body = rack_request.body.read
        rack_request.body.rewind
        timestamp = rack_request.env["HTTP_X_SLACK_REQUEST_TIMESTAMP"]
        signature = rack_request.env["HTTP_X_SLACK_SIGNATURE"]

        raise ChatSDK::SignatureVerificationError, "Missing Slack signature headers" unless timestamp && signature

        sig_basestring = "v0:#{timestamp}:#{body}"
        hex_digest = OpenSSL::HMAC.hexdigest("SHA256", @signing_secret, sig_basestring)
        computed = "v0=#{hex_digest}"

        unless Rack::Utils.secure_compare(computed, signature)
          raise ChatSDK::SignatureVerificationError, "Invalid Slack signature"
        end

        age = Time.now.to_i - timestamp.to_i
        if age.abs > 300
          raise ChatSDK::SignatureVerificationError, "Slack request too old (#{age}s)"
        end

        true
      end

      def ack_response(rack_request)
        body = rack_request.body.read
        rack_request.body.rewind

        parsed = parse_body(body, rack_request.content_type)
        return nil unless parsed

        if parsed["type"] == "url_verification"
          [200, {"content-type" => "text/plain"}, [parsed["challenge"]]]
        end
      end

      def parse_events(rack_request)
        body = rack_request.body.read
        rack_request.body.rewind

        parsed = parse_body(body, rack_request.content_type)
        return [] unless parsed

        EventParser.parse(parsed)
      end

      # Outbound
      def post_message(channel_id:, message:, thread_id: nil)
        msg = ChatSDK::PostableMessage.from(message)
        params = {channel: channel_id}
        params[:thread_ts] = thread_id if thread_id

        apply_message_params(params, msg)

        result = @client.chat_postMessage(**params)

        ChatSDK::Message.new(
          id: result["ts"],
          text: msg.text || "",
          author: ChatSDK::Author.new(id: "bot", name: "bot", platform: :slack, bot: true),
          thread_id: thread_id || result["ts"],
          channel_id: channel_id,
          platform: :slack,
          raw: result
        )
      end

      def edit_message(channel_id:, message_id:, message:)
        msg = ChatSDK::PostableMessage.from(message)
        params = {channel: channel_id, ts: message_id}

        apply_message_params(params, msg)

        @client.chat_update(**params)
      end

      def delete_message(channel_id:, message_id:)
        @client.chat_delete(channel: channel_id, ts: message_id)
      end

      def post_ephemeral(channel_id:, user_id:, message:, thread_id: nil)
        msg = ChatSDK::PostableMessage.from(message)
        params = {channel: channel_id, user: user_id}
        params[:thread_ts] = thread_id if thread_id

        apply_message_params(params, msg)

        @client.chat_postEphemeral(**params)
      end

      def upload_file(channel_id:, io:, filename:, thread_id: nil, comment: nil)
        params = {channels: channel_id, file: Faraday::Multipart::FilePart.new(io, nil, filename)}
        params[:thread_ts] = thread_id if thread_id
        params[:initial_comment] = comment if comment
        @client.files_upload(**params)
      end

      def add_reaction(channel_id:, message_id:, emoji:)
        @client.reactions_add(channel: channel_id, timestamp: message_id, name: emoji)
      end

      def remove_reaction(channel_id:, message_id:, emoji:)
        @client.reactions_remove(channel: channel_id, timestamp: message_id, name: emoji)
      end

      def get_user(user_id)
        result = @client.users_info(user: user_id)
        return nil unless result&.dig("user", "id")

        ChatSDK::Author.new(
          id: result.dig("user", "id"),
          name: result.dig("user", "name"),
          platform: :slack,
          bot: result.dig("user", "is_bot") || false,
          raw: result
        )
      end

      def open_dm(user_id)
        result = @client.conversations_open(users: user_id)
        result["channel"]["id"]
      end

      def fetch_messages(channel_id:, thread_id: nil, cursor: nil, limit: 50)
        result = if thread_id
          @client.conversations_replies(channel: channel_id, ts: thread_id, cursor: cursor, limit: limit)
        else
          @client.conversations_history(channel: channel_id, cursor: cursor, limit: limit)
        end
        messages = result["messages"].map { |m| parse_slack_message(m, channel_id) }
        [messages, result["response_metadata"]&.dig("next_cursor")]
      end

      def open_modal(trigger_id:, modal:)
        view = @modal_renderer.render(modal)
        @client.views_open(trigger_id: trigger_id, view: view)
      end

      def start_typing(channel_id:, thread_id: nil)
        # Slack doesn't have a native typing indicator API for bots
        # This is a no-op but the capability is declared for streaming support
      end

      def mention(user_id)
        "<@#{user_id}>"
      end

      def render(postable_message)
        if postable_message.card?
          @renderer.render(postable_message.card)
        else
          postable_message.text
        end
      end

      private

      def apply_message_params(params, msg)
        if msg.card?
          params[:blocks] = @renderer.render(msg.card)
          params[:text] = msg.text || msg.card.fallback_text
        else
          params[:text] = msg.text
        end
      end

      def parse_body(body, content_type)
        if content_type&.include?("application/json")
          JSON.parse(body)
        elsif content_type&.include?("application/x-www-form-urlencoded")
          params = Rack::Utils.parse_query(body)
          if params["payload"]
            JSON.parse(params["payload"])
          else
            params
          end
        else
          begin
            JSON.parse(body)
          rescue JSON::ParserError
            nil
          end
        end
      end

      def parse_slack_message(data, channel_id)
        ChatSDK::Message.new(
          id: data["ts"],
          text: data["text"] || "",
          author: ChatSDK::Author.new(
            id: data["user"] || data["bot_id"] || "unknown",
            name: data["username"] || data["user"] || "unknown",
            platform: :slack,
            bot: !!data["bot_id"]
          ),
          thread_id: data["thread_ts"] || data["ts"],
          channel_id: channel_id,
          platform: :slack,
          timestamp: data["ts"],
          raw: data
        )
      end
    end
  end
end
