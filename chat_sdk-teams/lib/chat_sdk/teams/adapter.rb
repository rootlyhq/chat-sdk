# frozen_string_literal: true

require "uri"

module ChatSDK
  module Teams
    class Adapter < ChatSDK::Adapter::Base
      DEFAULT_SERVICE_URL = "https://smba.trafficmanager.net/teams/"
      USER_SERVICE_URL_TTL = 30 * 24 * 60 * 60
      VERIFIED_JWT_CLAIMS_ENV_KEY = "chat_sdk.teams.verified_jwt_claims"

      capabilities :edit_messages, :delete_messages, :threads, :direct_messages,
        :file_uploads, :streaming_edit, :typing_indicator, :message_history

      attr_reader :client

      def initialize(app_id: nil, app_password: nil, tenant_id: nil,
        graph_client_id: nil, graph_client_secret: nil, graph_tenant_id: nil,
        service_url: nil)
        @app_id = app_id || ENV["TEAMS_APP_ID"]
        @app_password = app_password || ENV["TEAMS_APP_PASSWORD"]
        @tenant_id = tenant_id || ENV["TEAMS_TENANT_ID"]

        raise ChatSDK::ConfigurationError, "Teams app_id required" unless @app_id
        raise ChatSDK::ConfigurationError, "Teams app_password required" unless @app_password

        @graph_client_id = graph_client_id || ENV["TEAMS_GRAPH_CLIENT_ID"]
        @graph_client_secret = graph_client_secret || ENV["TEAMS_GRAPH_CLIENT_SECRET"]
        @graph_tenant_id = graph_tenant_id || ENV["TEAMS_GRAPH_TENANT_ID"]
        @graph_client = GraphClient.new(@graph_client_id, @graph_client_secret, @graph_tenant_id) if @graph_client_id
        @default_service_url = service_url || ENV["TEAMS_SERVICE_URL"] || DEFAULT_SERVICE_URL

        @client = BotFrameworkClient.new(app_id: @app_id, app_password: @app_password)
        @jwt_verifier = JwtVerifier.new(app_id: @app_id)
        @renderer = AdaptiveCardRenderer.new
        @service_urls = {}
      end

      def set_state(state)
        @state = state
      end

      def name
        :teams
      end

      # Inbound
      def verify_request!(rack_request)
        auth_header = rack_request.env["HTTP_AUTHORIZATION"]
        raise ChatSDK::SignatureVerificationError, "Missing authorization header" unless auth_header

        token = auth_header.sub(/^Bearer\s+/i, "")
        rack_request.env[VERIFIED_JWT_CLAIMS_ENV_KEY] = @jwt_verifier.verify!(token)
        true
      end

      def parse_events(rack_request)
        activity = read_json_body(rack_request)

        conversation_id = activity.dig("conversation", "id")
        claims = rack_request.env[VERIFIED_JWT_CLAIMS_ENV_KEY]
        if trusted_service_url?(activity["serviceUrl"], claims)
          register_service_url(conversation_id, activity["serviceUrl"]) if conversation_id
          user_id = activity.dig("from", "id")
          @state&.set(user_service_url_key(user_id), activity["serviceUrl"], ttl: USER_SERVICE_URL_TTL) if user_id
        end

        ActivityParser.parse(activity, bot_app_id: @app_id)
      rescue JSON::ParserError
        []
      end

      # Outbound
      def post_message(channel_id:, message:, thread_id: nil)
        msg = ChatSDK::PostableMessage.from(message)
        service_url = service_url_for(channel_id)

        activity = build_activity(msg)
        activity["replyToId"] = activity_reply_id(channel_id, thread_id) if thread_id

        result = @client.send_activity(
          service_url: service_url,
          conversation_id: channel_id,
          activity: activity
        )

        ChatSDK::Message.new(
          id: result["id"],
          text: msg.text || "",
          author: ChatSDK::Author.new(id: @app_id, name: "bot", platform: :teams, bot: true),
          thread_id: thread_id || channel_thread_id(channel_id, result["id"]),
          channel_id: channel_id,
          platform: :teams,
          raw: result
        )
      end

      def edit_message(channel_id:, message_id:, message:, **_options)
        require_capability!(:edit_messages)
        msg = ChatSDK::PostableMessage.from(message)
        service_url = service_url_for(channel_id)

        activity = build_activity(msg)
        activity["id"] = message_id

        @client.update_activity(
          service_url: service_url,
          conversation_id: channel_id,
          activity_id: message_id,
          activity: activity
        )
      end

      def delete_message(channel_id:, message_id:, **_options)
        require_capability!(:delete_messages)
        service_url = service_url_for(channel_id)

        @client.delete_activity(
          service_url: service_url,
          conversation_id: channel_id,
          activity_id: message_id
        )
      end

      def post_ephemeral(channel_id:, user_id:, message:, thread_id: nil)
        super # raises NotSupportedError
      end

      def upload_file(channel_id:, io:, filename:, thread_id: nil, comment: nil)
        require_capability!(:file_uploads)
        # Teams file uploads are done via attachments in activities
        service_url = service_url_for(channel_id)
        content = Base64.strict_encode64(io.read)

        activity = {
          "type" => "message",
          "text" => comment || "",
          "attachments" => [{
            "contentType" => "application/octet-stream",
            "name" => filename,
            "contentUrl" => "data:application/octet-stream;base64,#{content}"
          }]
        }
        activity["replyToId"] = activity_reply_id(channel_id, thread_id) if thread_id

        @client.send_activity(
          service_url: service_url,
          conversation_id: channel_id,
          activity: activity
        )
      end

      def open_dm(user_id)
        require_capability!(:direct_messages)
        service_url = @state&.get(user_service_url_key(user_id)) || @service_urls.values.first || @default_service_url

        payload = {
          "bot" => {"id" => @app_id},
          "members" => [{"id" => user_id}],
          "isGroup" => false
        }

        result = @client.create_conversation(service_url: service_url, payload: payload)
        conversation_id = result["id"]
        register_service_url(conversation_id, service_url)
        conversation_id
      end

      def open_modal(trigger_id:, modal:)
        super
      end

      def start_typing(channel_id:, thread_id: nil, message_id: nil)
        service_url = service_url_for(channel_id)
        @client.send_typing(
          service_url: service_url,
          conversation_id: channel_id
        )
      end

      def mention(user_id)
        "<at>#{user_id}</at>"
      end

      def render(postable_message)
        msg = ChatSDK::PostableMessage.from(postable_message)
        if msg.card?
          @renderer.render(msg.card)
        else
          msg.text
        end
      end

      def fetch_messages(channel_id:, thread_id: nil, cursor: nil, limit: 50)
        require_capability!(:message_history)
        unless @graph_client
          raise ChatSDK::ConfigurationError,
            "Teams message history requires Graph API credentials " \
            "(TEAMS_GRAPH_CLIENT_ID, TEAMS_GRAPH_CLIENT_SECRET, TEAMS_GRAPH_TENANT_ID)"
        end

        result = @graph_client.fetch_messages(chat_id: channel_id, limit: limit, cursor: cursor)
        messages = (result["value"] || []).map { |m| parse_graph_message(m, channel_id) }
        next_link = result["@odata.nextLink"]
        [messages, next_link]
      end

      # Store a service URL for a conversation (useful when sending proactive messages)
      def register_service_url(conversation_id, service_url)
        @service_urls[conversation_id] = service_url
        @state&.set(service_url_key(conversation_id), service_url)
      end

      def webhook_response(events)
        return unless events.any? { |event| event.raw.is_a?(Hash) && event.raw["type"] == "invoke" }

        body = {
          "statusCode" => 200,
          "type" => "application/vnd.microsoft.activity.message",
          "value" => "OK"
        }
        [200, {"content-type" => "application/json"}, [JSON.generate(body)]]
      end

      private

      def build_activity(postable_message)
        activity = {"type" => "message"}

        if postable_message.card?
          card_json = @renderer.render(postable_message.card)
          activity["attachments"] = [{
            "contentType" => "application/vnd.microsoft.card.adaptive",
            "content" => card_json
          }]
          activity["text"] = postable_message.text || postable_message.card.fallback_text
        else
          activity["text"] = postable_message.text
        end

        if postable_message.ai_generated
          activity["entities"] = [{
            "type" => "https://schema.org/Message",
            "@type" => "Message",
            "@context" => "https://schema.org",
            "additionalType" => ["AIGeneratedContent"]
          }]
        end

        activity
      end

      def service_url_for(channel_id)
        url = @service_urls[channel_id] || @state&.get(service_url_key(channel_id)) || @default_service_url
        unless url
          raise ChatSDK::PlatformError.new(
            "No service URL for conversation #{channel_id}. Register it first or receive an activity.",
            adapter_name: :teams
          )
        end
        url
      end

      def service_url_key(conversation_id)
        "chat_sdk:teams:service_url:#{conversation_id}"
      end

      def user_service_url_key(user_id)
        "chat_sdk:teams:user_service_url:#{user_id}"
      end

      def trusted_service_url?(service_url, claims)
        return false unless service_url.is_a?(String)

        uri = URI.parse(service_url)
        return false unless uri.scheme&.casecmp?("https") && uri.host

        service_url_claim = claims.is_a?(Hash) ? claims["serviceurl"] : nil
        service_url_claim.nil? ||
          (service_url_claim.is_a?(String) &&
            normalize_service_url(service_url) == normalize_service_url(service_url_claim))
      rescue URI::InvalidURIError
        false
      end

      def normalize_service_url(service_url)
        uri = URI.parse(service_url)
        return unless uri.scheme && uri.host

        uri.scheme = uri.scheme.downcase
        uri.host = uri.host.downcase
        uri.path = uri.path.delete_suffix("/")
        uri.to_s
      rescue URI::InvalidURIError
        nil
      end

      def channel_thread_id(channel_id, activity_id)
        return activity_id unless channel_id.to_s.include?("@thread.tacv2") && activity_id

        "#{channel_id};messageid=#{activity_id}"
      end

      def activity_reply_id(channel_id, thread_id)
        prefix = "#{channel_id};messageid="
        thread_id.start_with?(prefix) ? thread_id.delete_prefix(prefix) : thread_id
      end

      def parse_graph_message(data, channel_id)
        from = data["from"] || {}
        user = from["user"] || from["application"] || {}
        is_bot = !from["application"].nil?
        attachments = Array(data["attachments"]).filter_map do |attachment|
          next unless attachment["contentType"] == "reference" && attachment["contentUrl"]

          begin
            resolved = @graph_client.resolve_reference_attachment(content_url: attachment["contentUrl"])
            resolved.merge("filename" => resolved["filename"] || attachment["name"])
          rescue ChatSDK::PlatformError, ArgumentError, Faraday::Error
            nil
          end
        end

        ChatSDK::Message.new(
          id: data["id"],
          text: data.dig("body", "content") || "",
          author: ChatSDK::Author.new(
            id: user["id"] || "unknown",
            name: user["displayName"] || "unknown",
            platform: :teams,
            bot: is_bot,
            me: is_bot && user["id"] == @app_id
          ),
          thread_id: data["replyToId"] || data["id"],
          channel_id: channel_id,
          platform: :teams,
          attachments: attachments,
          timestamp: data["createdDateTime"],
          raw: data
        )
      end
    end
  end
end
