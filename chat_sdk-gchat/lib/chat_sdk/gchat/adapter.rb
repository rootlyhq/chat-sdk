# frozen_string_literal: true

module ChatSDK
  module GChat
    class Adapter < ChatSDK::Adapter::Base
      include ChatSDK::GChat::ResourceName

      capabilities :edit_messages, :delete_messages, :ephemeral_messages,
        :threads, :direct_messages, :message_history,
        :reactions, :streaming_edit

      def initialize(
        project_number: nil,
        endpoint_url: nil,
        pubsub_audience: nil,
        pubsub_service_account_email: nil,
        workspace_add_on_service_account_email: nil,
        disable_signature_verification: ENV["GOOGLE_CHAT_DISABLE_SIGNATURE_VERIFICATION"] == "true",
        credentials: nil,
        credentials_resolver: nil
      )
        @project_number = normalize_config_value(project_number || ENV["GOOGLE_CHAT_PROJECT_NUMBER"])
        @endpoint_url = normalize_config_value(endpoint_url)
        @pubsub_audience = normalize_config_value(pubsub_audience || ENV["GOOGLE_CHAT_PUBSUB_AUDIENCE"])
        @pubsub_service_account_email = normalize_config_value(
          pubsub_service_account_email || ENV["GOOGLE_CHAT_PUBSUB_SERVICE_ACCOUNT_EMAIL"]
        )
        @workspace_add_on_service_account_email = normalize_config_value(
          workspace_add_on_service_account_email || ENV["GOOGLE_CHAT_WORKSPACE_ADDON_SERVICE_ACCOUNT_EMAIL"]
        )
        @disable_signature_verification = if disable_signature_verification.nil?
          ENV["GOOGLE_CHAT_DISABLE_SIGNATURE_VERIFICATION"] == "true"
        else
          disable_signature_verification
        end

        unless @project_number || @endpoint_url || @pubsub_audience || @disable_signature_verification
          raise ChatSDK::ConfigurationError,
            "Google Chat webhook verification requires project_number, endpoint_url, or pubsub_audience; " \
            "set disable_signature_verification to true to accept unverified requests"
        end

        @credentials = build_credentials(credentials)
        @credentials_resolver = credentials_resolver
        @credential_client_cache = {}
        @credential_client_cache_mutex = Mutex.new
        @credentials_context_key = :"chat_sdk_gchat_credentials_#{object_id}"
        @client = build_client(@credentials)
        @verifier = TokenVerifier.new(
          @project_number,
          endpoint_url: @endpoint_url,
          pubsub_audience: @pubsub_audience,
          pubsub_service_account_email: @pubsub_service_account_email,
          workspace_add_on_service_account_email: @workspace_add_on_service_account_email,
          disable_signature_verification: @disable_signature_verification
        )
        @renderer = CardV2Renderer.new
      end

      def client
        context = ::Thread.current[@credentials_context_key]
        return @client unless context

        client_for_credentials(context[:credentials])
      end

      def with_credentials(credentials)
        previous_context = ::Thread.current[@credentials_context_key]
        ::Thread.current[@credentials_context_key] = {credentials: credentials}
        yield
      ensure
        ::Thread.current[@credentials_context_key] = previous_context
      end

      def name
        :gchat
      end

      # Inbound
      def verify_request!(rack_request)
        @verifier.verify_request!(rack_request)
      end

      def parse_events(rack_request)
        payload = read_json_body(rack_request)
        return parse_pubsub_payload(payload) if PubSubPush.pubsub_push?(payload)

        EventParser.parse(payload)
      rescue JSON::ParserError
        []
      end

      # Parses a Pub/Sub push after its request has been verified with #verify_request!.
      # The standard webhook endpoint verifies and parses Pub/Sub pushes automatically.
      #
      # @param rack_request [Rack::Request] the incoming Pub/Sub push request
      # @return [Array<ChatSDK::Events::Base>] parsed events (empty on bad payload)
      def parse_pubsub_event(rack_request)
        envelope = read_json_body(rack_request)
        return [] unless PubSubPush.pubsub_push?(envelope)

        parse_pubsub_payload(envelope)
      rescue JSON::ParserError, ArgumentError
        []
      end

      # Outbound
      def post_message(channel_id:, message:, thread_id: nil)
        msg = ChatSDK::PostableMessage.from(message)
        request_body = build_message_body(msg)

        if thread_id
          request_body[:thread] = {name: "spaces/#{channel_id}/threads/#{thread_id}"}
        end

        result = client_for(channel_id).create_message(
          parent: "spaces/#{channel_id}",
          message: request_body
        )

        build_response_message(result, channel_id, msg)
      end

      def edit_message(channel_id:, message_id:, message:, **_options)
        require_capability!(:edit_messages)
        msg = ChatSDK::PostableMessage.from(message)
        request_body = build_message_body(msg)
        request_body[:name] = message_resource_name(channel_id, message_id)

        client_for(channel_id).update_message(
          message: request_body,
          update_mask: Google::Protobuf::FieldMask.new(paths: ["text", "cards_v2"])
        )
      end

      def delete_message(channel_id:, message_id:, **_options)
        require_capability!(:delete_messages)
        client_for(channel_id).delete_message(name: message_resource_name(channel_id, message_id))
      end

      def post_ephemeral(channel_id:, user_id:, message:, thread_id: nil)
        require_capability!(:ephemeral_messages)
        msg = ChatSDK::PostableMessage.from(message)
        request_body = build_message_body(msg)
        request_body[:private_message_viewer] = {name: "users/#{user_id}"}

        if thread_id
          request_body[:thread] = {name: "spaces/#{channel_id}/threads/#{thread_id}"}
        end

        result = client_for(channel_id).create_message(
          parent: "spaces/#{channel_id}",
          message: request_body
        )

        build_response_message(result, channel_id, msg)
      end

      def upload_file(channel_id:, io:, filename:, thread_id: nil, comment: nil)
        super
      end

      def add_reaction(channel_id:, message_id:, emoji:, **_options)
        require_capability!(:reactions)
        client_for(channel_id).create_reaction(
          parent: message_resource_name(channel_id, message_id),
          reaction: {
            emoji: {unicode: emoji}
          }
        )
      end

      def remove_reaction(channel_id:, message_id:, emoji:, **_options)
        require_capability!(:reactions)
        # Google Chat requires the reaction resource name to delete
        # We construct it from the emoji unicode
        client_for(channel_id).delete_reaction(
          name: "#{message_resource_name(channel_id, message_id)}/reactions/#{emoji}"
        )
      end

      def open_dm(user_id)
        require_capability!(:direct_messages)
        result = client_for(nil).setup_space(
          space: {space_type: "DIRECT_MESSAGE"},
          memberships: [{member: {name: "users/#{user_id}", type: "HUMAN"}}]
        )
        extract_id(result.name)
      end

      def fetch_messages(channel_id:, thread_id: nil, cursor: nil, limit: 50)
        require_capability!(:message_history)
        result = client_for(channel_id).list_messages(
          parent: "spaces/#{channel_id}",
          page_size: limit,
          page_token: cursor
        )

        messages = result.messages.map { |m| parse_gchat_message(m, channel_id) }
        [messages, result.next_page_token.to_s.empty? ? nil : result.next_page_token]
      end

      def open_modal(trigger_id:, modal:)
        super
      end

      def start_typing(channel_id:, thread_id: nil, message_id: nil)
        super
      end

      def mention(user_id)
        "<users/#{user_id}>"
      end

      def render(postable_message)
        if postable_message.card?
          @renderer.render(postable_message.card)
        else
          postable_message.text
        end
      end

      private

      def parse_pubsub_payload(envelope)
        data = envelope.dig("message", "data")
        return [] unless data

        decoded = JSON.parse(Base64.decode64(data))
        EventParser.parse(decoded)
      rescue JSON::ParserError, ArgumentError
        []
      end

      def normalize_config_value(value)
        return nil if value.nil?

        normalized = value.to_s
        normalized.empty? ? nil : normalized
      end

      def client_for(channel_id)
        context = ::Thread.current[@credentials_context_key]
        return client_for_credentials(context[:credentials]) if context

        credentials = @credentials_resolver.call(channel_id) if @credentials_resolver && channel_id
        return @client if credentials.nil?

        client_for_credentials(credentials)
      end

      def client_for_credentials(credentials)
        return @client if credentials.nil?

        cache_key = credential_cache_key(credentials)
        @credential_client_cache_mutex.synchronize do
          cached_entry = @credential_client_cache.delete(cache_key)
          if cached_entry
            @credential_client_cache[cache_key] = cached_entry
            return cached_entry[:client]
          end

          client = build_client(build_credentials(credentials))
          @credential_client_cache[cache_key] = {credentials: credentials, client: client}
          @credential_client_cache.shift while @credential_client_cache.size > 100
          client
        end
      end

      def credential_cache_key(credentials)
        service_account_key = case credentials
        when Hash
          credentials
        when String
          JSON.parse(File.read(credentials))
        end

        if service_account_key
          [
            :service_account,
            service_account_key["client_email"] || service_account_key[:client_email],
            service_account_key["private_key_id"] || service_account_key[:private_key_id]
          ]
        else
          [:object, credentials.object_id]
        end
      end

      def build_client(credentials)
        Google::Apps::Chat::V1::ChatService::Client.new do |config|
          config.credentials = credentials if credentials
        end
      end

      def build_credentials(credentials)
        case credentials
        when nil
          # Use Application Default Credentials
          Google::Auth.get_application_default(
            ["https://www.googleapis.com/auth/chat.bot"]
          )
        when String
          # Path to service account JSON
          Google::Auth::ServiceAccountCredentials.make_creds(
            json_key_io: File.open(credentials),
            scope: "https://www.googleapis.com/auth/chat.bot"
          )
        when Hash
          # Service account JSON as a hash
          Google::Auth::ServiceAccountCredentials.make_creds(
            json_key_io: StringIO.new(JSON.generate(credentials)),
            scope: "https://www.googleapis.com/auth/chat.bot"
          )
        else
          credentials
        end
      end

      def build_message_body(msg)
        body = {}

        if msg.card?
          rendered = @renderer.render(msg.card)
          body[:cards_v2] = rendered[:cards_v2] if rendered[:cards_v2]
          body[:text] = msg.text || msg.card.fallback_text
        else
          body[:text] = msg.text
        end

        body
      end

      def build_response_message(result, channel_id, msg)
        ChatSDK::Message.new(
          id: extract_id(result.name),
          text: msg.text || "",
          author: ChatSDK::Author.new(id: "bot", name: "bot", platform: :gchat, bot: true),
          thread_id: extract_id(result.thread&.name),
          channel_id: channel_id,
          platform: :gchat,
          raw: result
        )
      end

      def parse_gchat_message(msg, channel_id)
        sender = msg.sender
        ChatSDK::Message.new(
          id: extract_id(msg.name),
          text: msg.text || "",
          author: ChatSDK::Author.new(
            id: extract_id(sender&.name || "unknown"),
            name: sender&.display_name || "unknown",
            platform: :gchat,
            bot: sender&.type == :BOT
          ),
          thread_id: extract_id(msg.thread&.name),
          channel_id: channel_id,
          platform: :gchat,
          raw: msg
        )
      end
    end
  end
end
