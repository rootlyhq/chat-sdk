# frozen_string_literal: true

module ChatSDK
  module GChat
    class Adapter < ChatSDK::Adapter::Base
      include ChatSDK::GChat::ResourceName

      capabilities :edit_messages, :delete_messages, :ephemeral_messages,
        :threads, :direct_messages, :message_history,
        :reactions, :streaming_edit

      attr_reader :client

      def initialize(project_number:, credentials: nil)
        @project_number = project_number.to_s

        raise ChatSDK::ConfigurationError, "Google Chat project_number required" if @project_number.empty?

        @credentials = build_credentials(credentials)
        @client = Google::Apps::Chat::V1::ChatService::Client.new do |config|
          config.credentials = @credentials if @credentials
        end
        @verifier = TokenVerifier.new(@project_number)
        @renderer = CardV2Renderer.new
      end

      def name
        :gchat
      end

      # Inbound
      def verify_request!(rack_request)
        auth_header = rack_request.env["HTTP_AUTHORIZATION"] || ""
        token = auth_header.sub(/\ABearer\s+/i, "")
        @verifier.verify!(token)
        true
      end

      def parse_events(rack_request)
        payload = read_json_body(rack_request)
        EventParser.parse(payload)
      rescue JSON::ParserError
        []
      end

      # Parses a Google Cloud Pub/Sub push message containing a Google Chat event.
      #
      # When a Pub/Sub subscription is configured externally (via Google Cloud
      # Console or Terraform) for Google Workspace Events, push messages arrive
      # as HTTP POSTs with the Chat event base64-encoded inside
      # `message.data`. This method decodes the envelope and delegates to
      # {EventParser}.
      #
      # @param rack_request [Rack::Request] the incoming Pub/Sub push request
      # @return [Array<ChatSDK::Events::Base>] parsed events (empty on bad payload)
      def parse_pubsub_event(rack_request)
        envelope = read_json_body(rack_request)
        data = envelope.dig("message", "data")
        return [] unless data

        decoded = JSON.parse(Base64.decode64(data))
        EventParser.parse(decoded)
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

        result = @client.create_message(
          parent: "spaces/#{channel_id}",
          message: request_body
        )

        build_response_message(result, channel_id, msg)
      end

      def edit_message(channel_id:, message_id:, message:)
        require_capability!(:edit_messages)
        msg = ChatSDK::PostableMessage.from(message)
        request_body = build_message_body(msg)
        request_body[:name] = "spaces/#{channel_id}/messages/#{message_id}"

        @client.update_message(
          message: request_body,
          update_mask: Google::Protobuf::FieldMask.new(paths: ["text", "cards_v2"])
        )
      end

      def delete_message(channel_id:, message_id:)
        require_capability!(:delete_messages)
        @client.delete_message(name: "spaces/#{channel_id}/messages/#{message_id}")
      end

      def post_ephemeral(channel_id:, user_id:, message:, thread_id: nil)
        require_capability!(:ephemeral_messages)
        msg = ChatSDK::PostableMessage.from(message)
        request_body = build_message_body(msg)
        request_body[:private_message_viewer] = {name: "users/#{user_id}"}

        if thread_id
          request_body[:thread] = {name: "spaces/#{channel_id}/threads/#{thread_id}"}
        end

        result = @client.create_message(
          parent: "spaces/#{channel_id}",
          message: request_body
        )

        build_response_message(result, channel_id, msg)
      end

      def upload_file(channel_id:, io:, filename:, thread_id: nil, comment: nil)
        super
      end

      def add_reaction(channel_id:, message_id:, emoji:)
        require_capability!(:reactions)
        @client.create_reaction(
          parent: "spaces/#{channel_id}/messages/#{message_id}",
          reaction: {
            emoji: {unicode: emoji}
          }
        )
      end

      def remove_reaction(channel_id:, message_id:, emoji:)
        require_capability!(:reactions)
        # Google Chat requires the reaction resource name to delete
        # We construct it from the emoji unicode
        @client.delete_reaction(
          name: "spaces/#{channel_id}/messages/#{message_id}/reactions/#{emoji}"
        )
      end

      def open_dm(user_id)
        require_capability!(:direct_messages)
        result = @client.setup_space(
          space: {space_type: "DIRECT_MESSAGE"},
          memberships: [{member: {name: "users/#{user_id}", type: "HUMAN"}}]
        )
        extract_id(result.name)
      end

      def fetch_messages(channel_id:, thread_id: nil, cursor: nil, limit: 50)
        require_capability!(:message_history)
        result = @client.list_messages(
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

      def start_typing(channel_id:, thread_id: nil)
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
