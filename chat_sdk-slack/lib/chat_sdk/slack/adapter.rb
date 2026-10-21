# frozen_string_literal: true

require "stringio"

module ChatSDK
  module Slack
    class Adapter < ChatSDK::Adapter::Base
      capabilities :edit_messages, :delete_messages, :ephemeral_messages,
        :file_uploads, :reactions, :modals, :typing_indicator,
        :streaming_edit, :threads, :direct_messages, :message_history,
        :scheduled_messages

      def initialize(bot_token: nil, signing_secret: nil,
        client_id: nil, client_secret: nil, proxy: nil, bot_user_id: nil,
        installation_provider: nil, encryption_key: nil, webhook_verifier: nil,
        native_streaming: true, stream_segment_max_age: 240)
        @bot_token = bot_token.nil? ? ENV["SLACK_BOT_TOKEN"] : bot_token
        @signing_secret = signing_secret || ENV["SLACK_SIGNING_SECRET"]
        @client_id = client_id || ENV["SLACK_CLIENT_ID"]
        @client_secret = client_secret || ENV["SLACK_CLIENT_SECRET"]
        @bot_user_id = bot_user_id || ENV["SLACK_BOT_USER_ID"]
        @installation_provider = installation_provider
        @webhook_verifier = webhook_verifier
        encryption_key ||= ENV["SLACK_ENCRYPTION_KEY"]
        @encryption_key = TokenEncryption.decode_key(encryption_key) if encryption_key
        valid_segment_max_age = stream_segment_max_age.is_a?(Numeric) &&
          !stream_segment_max_age.is_a?(Complex) &&
          !(stream_segment_max_age.respond_to?(:nan?) && stream_segment_max_age.nan?) &&
          (stream_segment_max_age.positive? || stream_segment_max_age == Float::INFINITY)
        unless valid_segment_max_age
          raise ChatSDK::ConfigurationError, "stream_segment_max_age must be a positive number"
        end
        @native_streaming = native_streaming
        @native_streaming_broken = false
        @stream_segment_max_age = stream_segment_max_age
        @bot_user_ids = {}
        @bot_user_id_mutex = Mutex.new
        @client_cache = {}
        @client_cache_mutex = Mutex.new
        @context_key = :"chat_sdk_slack_context_#{object_id}"
        @proxy = proxy || ENV["HTTPS_PROXY"] || ENV["https_proxy"]

        if !@bot_token.nil? && !@bot_token.is_a?(String) && !@bot_token.respond_to?(:call)
          raise ChatSDK::ConfigurationError, "Slack bot_token must be a String or callable"
        end
        if !@installation_provider.nil? && !@installation_provider.respond_to?(:get_installation) && !@installation_provider.respond_to?(:call)
          raise ChatSDK::ConfigurationError, "Slack installation_provider must respond to get_installation or call"
        end
        if !@webhook_verifier.nil? && !@webhook_verifier.respond_to?(:call)
          raise ChatSDK::ConfigurationError, "Slack webhook_verifier must be callable"
        end
        unless @bot_token || @client_id || @installation_provider
          raise ChatSDK::ConfigurationError, "Slack bot_token, client_id or installation_provider required"
        end
        if @webhook_verifier.nil? && !@signing_secret
          raise ChatSDK::ConfigurationError, "Slack signing_secret or webhook_verifier required"
        end

        if @bot_token.is_a?(String)
          ::Slack.configure do |config|
            config.token = @bot_token
          end
          @client = client_for_token(@bot_token)
        end

        @renderer = BlockKitRenderer.new
        @modal_renderer = ModalRenderer.new
      end

      # Returns the per-request client (multi-workspace) or the static client (single-workspace).
      def client
        request_context = context
        return client_for_token(request_context[:token]) if request_context && !request_context[:token].nil?
        return @client if @bot_token.is_a?(String)
        return unless @bot_token.respond_to?(:call)

        token = @bot_token.call
        if token.nil? || token == false || (token.respond_to?(:empty?) && token.empty?)
          raise ChatSDK::ConfigurationError, "Slack bot_token resolver returned no token"
        end
        client_for_token(token)
      end

      def multi_workspace?
        @bot_token.nil? || !@client_id.nil?
      end

      def with_bot_token(token, installation_id: nil)
        previous_context = context
        set_context(token: token, installation_id: installation_id)
        yield
      ensure
        set_context(previous_context)
      end

      # Inject state store after initialization (e.g., from Chat instance).
      def set_state(state)
        @state = state
      end

      # --- Multi-workspace installation management ---

      def set_installation(team_id, bot_token:, bot_user_id: nil, team_name: nil,
        enterprise_id: nil, enterprise_install: nil)
        raise ChatSDK::ConfigurationError, "Multi-workspace mode requires state" unless @state

        installation = {
          "bot_token" => @encryption_key ? TokenEncryption.encrypt(bot_token, @encryption_key) : bot_token,
          "bot_user_id" => bot_user_id,
          "team_name" => team_name
        }
        installation["enterprise_id"] = enterprise_id unless enterprise_id.nil?
        installation["is_enterprise_install"] = enterprise_install unless enterprise_install.nil?
        @state.set(installation_key(team_id), installation)
        invalidate_bot_user_id(team_id)
      end

      def get_installation(team_id)
        return nil unless @state

        installation = @state.get(installation_key(team_id))
        return installation unless installation.is_a?(Hash)

        token_key = installation.key?("bot_token") ? "bot_token" : :bot_token
        token = installation[token_key]
        return installation unless TokenEncryption.encrypted?(token)
        unless @encryption_key
          raise ChatSDK::ConfigurationError, "Slack installation token is encrypted; configure encryption_key"
        end

        installation.merge(token_key => TokenEncryption.decrypt(token, @encryption_key))
      end

      def delete_installation(team_id)
        invalidate_bot_user_id(team_id)
        return unless @state

        @state.delete(installation_key(team_id))
      end

      def handle_oauth_callback(code:, redirect_uri: nil)
        raise ChatSDK::ConfigurationError, "client_id required for OAuth" unless @client_id

        temp_client = build_client
        params = {
          client_id: @client_id,
          client_secret: @client_secret,
          code: code
        }
        params[:redirect_uri] = redirect_uri if redirect_uri

        result = temp_client.oauth_v2_access(**params)

        team = hash_value(result, "team")
        enterprise = hash_value(result, "enterprise")
        enterprise_install = truthy_slack_value?(hash_value(result, "is_enterprise_install"))
        enterprise_id = hash_value(enterprise, "id") || hash_value(result, "enterprise_id")
        team_id = hash_value(team, "id")
        installation_id = enterprise_install ? enterprise_id : team_id
        access_token = hash_value(result, "access_token")
        unless access_token && !access_token.empty? && installation_id && !installation_id.empty?
          missing = enterprise_install ? "access_token or enterprise.id" : "access_token or team.id"
          raise ChatSDK::ConfigurationError, "Slack OAuth response missing #{missing}"
        end

        installation = {
          "bot_token" => access_token,
          "bot_user_id" => hash_value(result, "bot_user_id"),
          "team_name" => hash_value(team, "name") || hash_value(enterprise, "name")
        }
        installation["enterprise_id"] = enterprise_id unless enterprise_id.nil?
        installation["is_enterprise_install"] = enterprise_install if hash_key?(result, "is_enterprise_install")

        set_installation(installation_id,
          bot_token: installation["bot_token"],
          bot_user_id: installation["bot_user_id"],
          team_name: installation["team_name"],
          enterprise_id: enterprise_id,
          enterprise_install: hash_key?(result, "is_enterprise_install") ? enterprise_install : nil)

        {
          team_id: installation_id,
          enterprise_id: enterprise_id,
          enterprise_install: enterprise_install,
          installation: installation
        }
      end

      def name
        :slack
      end

      # Inbound
      def verify_request!(rack_request)
        body = rack_request.body.read
        rack_request.body.rewind
        if @webhook_verifier
          begin
            result = @webhook_verifier.call(rack_request, body)
          rescue => e
            raise ChatSDK::SignatureVerificationError, "Slack webhook verifier failed: #{e.message}"
          end
          raise ChatSDK::SignatureVerificationError, "Slack webhook verifier rejected the request" unless result

          rack_request.env["rack.input"] = StringIO.new(result) if result.is_a?(String)
          return true
        end

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
        set_context(nil)
        body = rack_request.body.read
        rack_request.body.rewind

        parsed = parse_body(body, rack_request.content_type)
        return [] unless parsed

        return [] unless prepare_payload_context(parsed)

        events = EventParser.parse(parsed)
        classify_message_events(events, parsed)
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

      def stream(channel_id:, thread_id:, stream:, options: {})
        return unless thread_id && !thread_id.to_s.empty?
        direct_message = channel_id.to_s.start_with?("D")
        recipient_ids = [options[:recipient_user_id], options[:recipient_team_id]]
        has_recipient_context = recipient_ids.all? { |id| id && !id.to_s.empty? }
        return unless direct_message || has_recipient_context
        return unless @native_streaming && !@native_streaming_broken

        stream_client = client
        NativeStream.new(
          adapter: self,
          client: stream_client,
          channel_id: channel_id,
          thread_id: thread_id,
          stream: stream,
          options: options,
          max_age: @stream_segment_max_age
        ).run
      end

      def edit_message(channel_id:, message_id:, message:, **_options)
        msg = ChatSDK::PostableMessage.from(message)
        params = {channel: channel_id, ts: message_id}

        apply_message_params(params, msg)

        client.chat_update(**params)
      end

      def delete_message(channel_id:, message_id:, **_options)
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
        content = io.read
        io.rewind if io.respond_to?(:rewind)
        params = {channel_id: channel_id, filename: filename, content: content}
        params[:thread_ts] = thread_id if thread_id
        params[:initial_comment] = comment if comment
        client.files_upload_v2(**params)
      end

      def add_reaction(channel_id:, message_id:, emoji:, **_options)
        client.reactions_add(channel: channel_id, timestamp: message_id, name: emoji)
      end

      def remove_reaction(channel_id:, message_id:, emoji:, **_options)
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

      def update_modal(view_id:, modal:)
        client.views_update(view_id: view_id, view: @modal_renderer.render(modal))
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

      def send_to_response_url(response_url:, message:)
        msg = ChatSDK::PostableMessage.from(message)
        payload = {}
        apply_message_params(payload, msg)
        Faraday.post(response_url) do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = JSON.generate(payload)
        end
      end

      def fetch_thread(channel_id:, thread_id: nil)
        result = client.conversations_info(channel: channel_id)
        result["channel"]
      end

      def start_typing(channel_id:, thread_id: nil, message_id: nil)
        # Slack doesn't have a native typing indicator API for bots
        # This is a no-op but the capability is declared for streaming support
      end

      def concurrency_scope(event)
        return context[:installation_id] if context && context[:installation_id]
        return unless multi_workspace?

        raw = event.raw.is_a?(Hash) ? event.raw : {}
        raw_event = raw.is_a?(Hash) ? raw["event"] || raw[:event] || raw : {}
        raw_team = raw.is_a?(Hash) ? raw["team"] || raw[:team] : nil
        raw_team_id = raw_team.is_a?(Hash) ? raw_team["id"] || raw_team[:id] : raw_team
        raw_team_id || raw["team_id"] || raw[:team_id] ||
          raw_event["team_id"] || raw_event[:team_id] ||
          raw_event["team"] || raw_event[:team]
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
        raise ArgumentError, "start requires a block" unless block

        @socket_mode = SocketMode.new(app_token: app_token, bot_client: client)
        @socket_mode.start do |event, payload|
          payload ||= event.raw
          set_context(nil)
          next unless prepare_payload_context(payload)

          classify_message_events([event], payload)
          block.call(event)
        end
      end

      def stop_socket_mode
        @socket_mode&.stop
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

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def build_client(token: nil)
        options = {}
        options[:token] = token unless token.nil?
        options[:proxy] = @proxy if @proxy
        options.empty? ? ::Slack::Web::Client.new : ::Slack::Web::Client.new(options)
      end

      def classify_message_events(events, payload)
        events.each do |event|
          next unless %i[mention subscribed_message direct_message].include?(event.type)

          event.message.is_mention = classify_mention(event, payload)
        end
        events
      end

      def classify_mention(event, payload)
        raw_event = payload["event"] || {}
        return true if raw_event["type"] == "app_mention"

        bot_user_id = resolve_bot_user_id(event)
        return true if event.type == :mention && bot_user_id.nil?
        return nil if bot_user_id.nil?

        text = raw_event["text"].to_s
        masked_text = ChatSDK::Format::Mentions.mask_code_spans(text)
        text_mentions_bot = /<@#{Regexp.escape(bot_user_id)}(?:\|[^>]*)?>/.match?(masked_text)
        text_mentions_bot || rich_text_mentions_bot?(raw_event["blocks"], bot_user_id)
      end

      def resolve_bot_user_id(event)
        request_context = context
        return request_context[:bot_user_id] if request_context && request_context[:bot_user_id]

        return @bot_user_id if @bot_user_id

        installation_id = if multi_workspace?
          request_context&.[](:installation_id) || event_installation_id(event)
        end
        installation = resolve_installation(installation_id, enterprise_install: installation_enterprise_flag(event)) if installation_id && !request_context
        installation_bot_user_id = hash_value(installation, "bot_user_id")
        return installation_bot_user_id if installation_bot_user_id

        token = request_context&.[](:token) || hash_value(installation, "bot_token")
        current_client = token ? client_for_token(token) : client
        return unless current_client

        @bot_user_id_mutex.synchronize do
          cache_key = multi_workspace? ? (installation_id || :default) : :default
          return @bot_user_ids[cache_key] if @bot_user_ids.key?(cache_key)

          bot_user_id = begin
            current_client.auth_test["user_id"]
          rescue ::Slack::Web::Api::Errors::SlackError, Faraday::Error, SocketError, Timeout::Error
            nil
          end
          @bot_user_ids[cache_key] = bot_user_id if bot_user_id
          bot_user_id
        end
      end

      def invalidate_bot_user_id(team_id)
        @bot_user_id_mutex.synchronize { @bot_user_ids.delete(team_id) }
      end

      def rich_text_mentions_bot?(blocks, bot_user_id)
        Array(blocks).any? { |block| rich_text_element_mentions_bot?(block, bot_user_id) }
      end

      def rich_text_element_mentions_bot?(element, bot_user_id)
        return false unless element.is_a?(Hash)
        return false if %w[rich_text_preformatted preformatted code].include?(element["type"])
        return false if element.dig("style", "code")
        return true if element["type"] == "user" && element["user_id"] == bot_user_id

        Array(element["elements"]).any? { |child| rich_text_element_mentions_bot?(child, bot_user_id) }
      end

      def client_for_token(token)
        @client_cache_mutex.synchronize do
          return @client_cache[token] if @client_cache.key?(token)

          @client_cache[token] = build_client(token: token)
          @client_cache.shift while @client_cache.size > 256
          @client_cache[token]
        end
      end

      def context
        ::Thread.current[@context_key]
      end

      def set_context(value)
        ::Thread.current[@context_key] = value
      end

      def prepare_payload_context(payload)
        return true unless multi_workspace?

        identity = extract_installation(payload)
        return true unless identity

        installation = resolve_installation(
          identity[:installation_id],
          enterprise_install: identity[:enterprise_install]
        )
        token = hash_value(installation, "bot_token")
        unless installation && token && token != false && !(token.respond_to?(:empty?) && token.empty?)
          return true unless @bot_token.nil?

          ChatSDK::Log.warn("Dropping Slack event without a resolved installation for #{identity[:installation_id]}")
          return false
        end

        set_context({
          token: token,
          bot_user_id: hash_value(installation, "bot_user_id"),
          installation_id: identity[:installation_id],
          enterprise_install: identity[:enterprise_install],
          team_id: identity[:team_id],
          enterprise_id: identity[:enterprise_id]
        })
        true
      end

      def resolve_installation(installation_id, enterprise_install:)
        return unless installation_id

        installation = if @installation_provider
          if @installation_provider.respond_to?(:get_installation)
            @installation_provider.get_installation(installation_id, enterprise_install: enterprise_install)
          else
            @installation_provider.call(installation_id, enterprise_install: enterprise_install)
          end
        else
          get_installation(installation_id)
        end
        unless installation
          ChatSDK::Log.warn("Slack installation not found for #{installation_id}")
          return
        end
        token = hash_value(installation, "bot_token")
        unless installation.is_a?(Hash) && token && token != false && !(token.respond_to?(:empty?) && token.empty?)
          ChatSDK::Log.warn("Slack installation for #{installation_id} has no bot_token")
          return
        end

        installation
      rescue => e
        ChatSDK::Log.error("Could not resolve Slack installation #{installation_id}: #{e.message}")
        nil
      end

      def extract_installation(payload)
        return unless payload.is_a?(Hash)

        if hash_value(payload, "type") == "event_callback"
          authorization = Array(hash_value(payload, "authorizations")).first
          enterprise_flag = if hash_key?(authorization, "is_enterprise_install")
            hash_value(authorization, "is_enterprise_install")
          else
            hash_value(payload, "is_enterprise_install")
          end
          enterprise_install = truthy_slack_value?(enterprise_flag)
          team_id = hash_value(authorization, "team_id") || hash_value(payload, "team_id")
          enterprise_id = hash_value(authorization, "enterprise_id") || hash_value(payload, "enterprise_id")
        elsif hash_key?(payload, "command")
          enterprise_install = hash_value(payload, "is_enterprise_install") == "true"
          team_id = hash_value(payload, "team_id")
          enterprise_id = hash_value(payload, "enterprise_id")
        else
          enterprise_install = truthy_slack_value?(hash_value(payload, "is_enterprise_install"))
          team = hash_value(payload, "team")
          enterprise = hash_value(payload, "enterprise")
          team_id = hash_value(team, "id") || hash_value(payload, "team_id")
          enterprise_id = hash_value(enterprise, "id") || hash_value(payload, "enterprise_id")
        end

        installation_id = enterprise_install ? enterprise_id : team_id
        return unless installation_id

        {
          installation_id: installation_id,
          enterprise_install: enterprise_install,
          team_id: team_id,
          enterprise_id: enterprise_id
        }
      end

      def event_installation_id(event)
        raw = event.raw.is_a?(Hash) ? event.raw : {}
        extract_installation(raw)&.[](:installation_id) ||
          hash_value(raw, "team_id") ||
          hash_value(hash_value(raw, "team"), "id")
      end

      def installation_enterprise_flag(event)
        raw = event.raw.is_a?(Hash) ? event.raw : {}
        identity = extract_installation(raw)
        identity ? identity[:enterprise_install] : truthy_slack_value?(hash_value(raw, "is_enterprise_install"))
      end

      def hash_value(hash, key)
        return unless hash.is_a?(Hash)

        hash.key?(key) ? hash[key] : hash[key.to_sym]
      end

      def hash_key?(hash, key)
        hash.is_a?(Hash) && (hash.key?(key) || hash.key?(key.to_sym))
      end

      def truthy_slack_value?(value)
        value == true || value == "true"
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
