# frozen_string_literal: true

module ChatSDK
  module Slack
    class Adapter < ChatSDK::Adapter::Base
      capabilities :edit_messages, :delete_messages, :ephemeral_messages,
        :file_uploads, :reactions, :modals, :typing_indicator,
        :streaming_edit, :threads, :direct_messages, :message_history,
        :scheduled_messages

      def initialize(bot_token: nil, signing_secret: nil,
        client_id: nil, client_secret: nil)
        @bot_token = bot_token || ENV["SLACK_BOT_TOKEN"]
        @signing_secret = signing_secret || ENV["SLACK_SIGNING_SECRET"]
        @client_id = client_id || ENV["SLACK_CLIENT_ID"]
        @client_secret = client_secret || ENV["SLACK_CLIENT_SECRET"]

        unless @bot_token || @client_id
          raise ChatSDK::ConfigurationError, "Slack bot_token or client_id required"
        end
        raise ChatSDK::ConfigurationError, "Slack signing_secret required" unless @signing_secret

        if @bot_token
          ::Slack.configure do |config|
            config.token = @bot_token
          end
          @client = ::Slack::Web::Client.new(token: @bot_token)
        end

        @renderer = BlockKitRenderer.new
        @modal_renderer = ModalRenderer.new
        @team_clients = {}
      end

      # Returns the per-request client (multi-workspace) or the static client (single-workspace).
      def client
        ::Thread.current[:chat_sdk_slack_client] || @client
      end

      # Inject state store after initialization (e.g., from Chat instance).
      def set_state(state)
        @state = state
      end

      # --- Multi-workspace installation management ---

      def set_installation(team_id, bot_token:, bot_user_id: nil, team_name: nil)
        raise ChatSDK::ConfigurationError, "Multi-workspace mode requires state" unless @state

        @team_clients.delete(team_id)
        @state.set(installation_key(team_id), {
          "bot_token" => bot_token,
          "bot_user_id" => bot_user_id,
          "team_name" => team_name
        })
      end

      def get_installation(team_id)
        return nil unless @state

        @state.get(installation_key(team_id))
      end

      def delete_installation(team_id)
        @team_clients.delete(team_id)
        return unless @state

        @state.delete(installation_key(team_id))
      end

      def handle_oauth_callback(code:, redirect_uri: nil)
        raise ChatSDK::ConfigurationError, "client_id required for OAuth" unless @client_id

        temp_client = ::Slack::Web::Client.new
        params = {
          client_id: @client_id,
          client_secret: @client_secret,
          code: code
        }
        params[:redirect_uri] = redirect_uri if redirect_uri

        result = temp_client.oauth_v2_access(**params)

        team_id = result["team"]["id"]
        installation = {
          "bot_token" => result["access_token"],
          "bot_user_id" => result["bot_user_id"],
          "team_name" => result["team"]["name"]
        }

        set_installation(team_id,
          bot_token: installation["bot_token"],
          bot_user_id: installation["bot_user_id"],
          team_name: installation["team_name"])

        {team_id: team_id, installation: installation}
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

        # Multi-workspace: resolve per-team client from payload
        # Clear any stale client from a previous request on this thread (Puma thread pool safety)
        if @client_id
          ::Thread.current[:chat_sdk_slack_client] = nil
          team_id = parsed["team_id"] || parsed.dig("team", "id")
          resolve_team_client(team_id) if team_id
        end

        EventParser.parse(parsed)
      end

      # Outbound
      def post_message(channel_id:, message:, thread_id: nil)
        msg = ChatSDK::PostableMessage.from(message)
        params = {channel: channel_id}
        params[:thread_ts] = thread_id if thread_id

        apply_message_params(params, msg)

        result = client.chat_postMessage(**params)

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

        client.chat_update(**params)
      end

      def delete_message(channel_id:, message_id:)
        client.chat_delete(channel: channel_id, ts: message_id)
      end

      def post_ephemeral(channel_id:, user_id:, message:, thread_id: nil)
        msg = ChatSDK::PostableMessage.from(message)
        params = {channel: channel_id, user: user_id}
        params[:thread_ts] = thread_id if thread_id

        apply_message_params(params, msg)

        client.chat_postEphemeral(**params)
      end

      def upload_file(channel_id:, io:, filename:, thread_id: nil, comment: nil)
        params = {channels: channel_id, file: Faraday::Multipart::FilePart.new(io, nil, filename)}
        params[:thread_ts] = thread_id if thread_id
        params[:initial_comment] = comment if comment
        client.files_upload(**params)
      end

      def add_reaction(channel_id:, message_id:, emoji:)
        client.reactions_add(channel: channel_id, timestamp: message_id, name: emoji)
      end

      def remove_reaction(channel_id:, message_id:, emoji:)
        client.reactions_remove(channel: channel_id, timestamp: message_id, name: emoji)
      end

      def get_user(user_id)
        result = client.users_info(user: user_id)
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
        result = client.conversations_open(users: user_id)
        result["channel"]["id"]
      end

      def schedule_message(channel_id:, message:, post_at:, thread_id: nil)
        msg = ChatSDK::PostableMessage.from(message)
        text = msg.text || ""

        params = {channel: channel_id, text: text, post_at: post_at.to_i}
        params[:thread_ts] = thread_id if thread_id

        result = client.chat_scheduleMessage(**params)

        ChatSDK::Message.new(
          id: result["scheduled_message_id"],
          text: text,
          author: ChatSDK::Author.new(id: "bot", name: "bot", platform: :slack, bot: true),
          thread_id: thread_id || result["scheduled_message_id"],
          channel_id: channel_id,
          platform: :slack,
          raw: result
        )
      end

      def fetch_messages(channel_id:, thread_id: nil, cursor: nil, limit: 50)
        result = if thread_id
          client.conversations_replies(channel: channel_id, ts: thread_id, cursor: cursor, limit: limit)
        else
          client.conversations_history(channel: channel_id, cursor: cursor, limit: limit)
        end
        messages = result["messages"].map { |m| parse_slack_message(m, channel_id) }
        [messages, result["response_metadata"]&.dig("next_cursor")]
      end

      def open_modal(trigger_id:, modal:)
        view = @modal_renderer.render(modal)
        client.views_open(trigger_id: trigger_id, view: view)
      end

      def publish_home_view(user_id:, view:)
        client.views_publish(user_id: user_id, view: view)
      end

      def set_suggested_prompts(channel_id:, thread_id:, prompts:)
        client.assistant_threads_setSuggestedPrompts(
          channel_id: channel_id,
          thread_ts: thread_id,
          prompts: prompts
        )
      end

      def set_assistant_status(channel_id:, thread_id:, status:)
        client.assistant_threads_setStatus(
          channel_id: channel_id,
          thread_ts: thread_id,
          status: status
        )
      end

      def set_assistant_title(channel_id:, thread_id:, title:)
        client.assistant_threads_setTitle(
          channel_id: channel_id,
          thread_ts: thread_id,
          title: title
        )
      end

      def start_typing(channel_id:, thread_id: nil)
        # Slack doesn't have a native typing indicator API for bots
        # This is a no-op but the capability is declared for streaming support
      end

      # Slack-specific: receive real-time events via Socket Mode WebSocket.
      # Requires the optional 'faye-websocket' gem and an app-level token (xapp-*).
      # Not part of the base adapter contract.
      #
      # Usage:
      #   adapter.start_socket_mode(app_token: "xapp-...") do |event|
      #     # event is a ChatSDK::Events::* instance
      #   end
      def start_socket_mode(app_token: nil, &block)
        app_token ||= ENV["SLACK_APP_TOKEN"]
        raise ChatSDK::ConfigurationError, "Slack app_token required for socket mode" unless app_token

        socket = SocketMode.new(app_token: app_token, bot_client: client)
        socket.start(&block)
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

      def resolve_team_client(team_id)
        return unless @client_id && @state

        cached = @team_clients[team_id]
        if cached
          ::Thread.current[:chat_sdk_slack_client] = cached
          return
        end

        installation = get_installation(team_id)
        return unless installation

        new_client = ::Slack::Web::Client.new(token: installation["bot_token"])
        @team_clients[team_id] = new_client
        ::Thread.current[:chat_sdk_slack_client] = new_client
      end

      def installation_key(team_id)
        "slack:installation:#{team_id}"
      end

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
