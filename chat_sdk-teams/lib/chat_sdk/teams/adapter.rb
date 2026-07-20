# frozen_string_literal: true

module ChatSDK
  module Teams
    class Adapter < ChatSDK::Adapter::Base
      capabilities :edit_messages, :delete_messages, :threads, :direct_messages,
        :file_uploads, :streaming_edit, :typing_indicator

      attr_reader :client

      def initialize(app_id: nil, app_password: nil, tenant_id: nil)
        @app_id = app_id || ENV["TEAMS_APP_ID"]
        @app_password = app_password || ENV["TEAMS_APP_PASSWORD"]
        @tenant_id = tenant_id || ENV["TEAMS_TENANT_ID"]

        raise ChatSDK::ConfigurationError, "Teams app_id required" unless @app_id
        raise ChatSDK::ConfigurationError, "Teams app_password required" unless @app_password

        @client = BotFrameworkClient.new(app_id: @app_id, app_password: @app_password)
        @jwt_verifier = JwtVerifier.new(app_id: @app_id)
        @renderer = AdaptiveCardRenderer.new
        @service_urls = {}
      end

      def name
        :teams
      end

      # Inbound
      def verify_request!(rack_request)
        auth_header = rack_request.env["HTTP_AUTHORIZATION"]
        raise ChatSDK::SignatureVerificationError, "Missing authorization header" unless auth_header

        token = auth_header.sub(/^Bearer\s+/i, "")
        @jwt_verifier.verify!(token)
        true
      end

      def parse_events(rack_request)
        activity = read_json_body(rack_request)

        # Cache the service URL for this conversation
        if activity["serviceUrl"] && activity.dig("conversation", "id")
          @service_urls[activity.dig("conversation", "id")] = activity["serviceUrl"]
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
        activity["replyToId"] = thread_id if thread_id

        result = @client.send_activity(
          service_url: service_url,
          conversation_id: channel_id,
          activity: activity
        )

        ChatSDK::Message.new(
          id: result["id"],
          text: msg.text || "",
          author: ChatSDK::Author.new(id: @app_id, name: "bot", platform: :teams, bot: true),
          thread_id: thread_id || result["id"],
          channel_id: channel_id,
          platform: :teams,
          raw: result
        )
      end

      def edit_message(channel_id:, message_id:, message:)
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

      def delete_message(channel_id:, message_id:)
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
        activity["replyToId"] = thread_id if thread_id

        @client.send_activity(
          service_url: service_url,
          conversation_id: channel_id,
          activity: activity
        )
      end

      # Teams Bot Framework API does not support adding/removing reactions
      # programmatically. Inbound reactions are still parsed from messageReaction
      # activities, but outbound reaction methods raise NotSupportedError.
      def add_reaction(channel_id:, message_id:, emoji:)
        super
      end

      def remove_reaction(channel_id:, message_id:, emoji:)
        super
      end

      def open_dm(user_id)
        require_capability!(:direct_messages)
        # To open a DM, we need a service URL. Use the first cached one.
        service_url = @service_urls.values.first
        unless service_url
          raise ChatSDK::PlatformError.new(
            "No service URL available. A Teams activity must be received first.",
            adapter_name: :teams
          )
        end

        payload = {
          "bot" => {"id" => @app_id},
          "members" => [{"id" => user_id}],
          "isGroup" => false
        }

        result = @client.create_conversation(service_url: service_url, payload: payload)
        conversation_id = result["id"]
        @service_urls[conversation_id] = service_url
        conversation_id
      end

      # Teams Bot Framework doesn't provide a message history API.
      # Fetching message history requires Microsoft Graph API with separate
      # credentials (graph_client_id, graph_client_secret, graph_tenant_id).
      def fetch_messages(channel_id:, thread_id: nil, cursor: nil, limit: 50)
        super
      end

      def open_modal(trigger_id:, modal:)
        super # raises NotSupportedError
      end

      def start_typing(channel_id:, thread_id: nil)
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

      # Store a service URL for a conversation (useful when sending proactive messages)
      def register_service_url(conversation_id, service_url)
        @service_urls[conversation_id] = service_url
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

        activity
      end

      def service_url_for(channel_id)
        url = @service_urls[channel_id]
        unless url
          raise ChatSDK::PlatformError.new(
            "No service URL for conversation #{channel_id}. Register it first or receive an activity.",
            adapter_name: :teams
          )
        end
        url
      end
    end
  end
end
