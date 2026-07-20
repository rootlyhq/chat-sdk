# frozen_string_literal: true

module ChatSDK
  module WhatsApp
    class Adapter < ChatSDK::Adapter::Base
      include ChatSDK::Adapter::MetaVerification

      capabilities :direct_messages, :file_uploads, :reactions

      attr_reader :client

      def initialize(access_token: nil, app_secret: nil, phone_number_id: nil, verify_token: nil)
        @access_token = access_token || ENV["WHATSAPP_ACCESS_TOKEN"]
        @app_secret = app_secret || ENV["WHATSAPP_APP_SECRET"]
        @phone_number_id = phone_number_id || ENV["WHATSAPP_PHONE_NUMBER_ID"]
        @verify_token = verify_token || ENV["WHATSAPP_VERIFY_TOKEN"]

        raise ChatSDK::ConfigurationError, "WhatsApp access_token required" unless @access_token
        raise ChatSDK::ConfigurationError, "WhatsApp phone_number_id required" unless @phone_number_id

        @client = ApiClient.new(@access_token, @phone_number_id)
        @renderer = InteractiveRenderer.new
      end

      def name
        :whatsapp
      end

      # Inbound
      def verify_request!(rack_request)
        verify_meta_signature!(rack_request, secret: @app_secret, platform_name: "WhatsApp")
      end

      def ack_response(rack_request)
        meta_ack_response(rack_request, verify_token: @verify_token)
      end

      def parse_events(rack_request)
        payload = read_json_body(rack_request)
        EventParser.parse(payload, @phone_number_id)
      rescue JSON::ParserError
        []
      end

      # Outbound
      def post_message(channel_id:, message:, thread_id: nil) # rubocop:disable Lint/UnusedMethodArgument
        payload = prepare_message_payload(message)

        result = if payload[:type] == "text" && payload.dig(:text, :body)
          chunks = split_message(payload[:text][:body])
          chunks.reduce(nil) do |_, chunk|
            @client.send_message(to: channel_id, type: "text", text: {body: chunk})
          end
        else
          @client.send_message(to: channel_id, **payload)
        end

        parse_whatsapp_message(result, channel_id)
      end

      def post_template(channel_id:, template_name:, language_code: "en", components: nil)
        @client.send_template(to: channel_id, template_name: template_name, language_code: language_code, components: components)
      end

      def mark_as_read(message_id:)
        @client.mark_as_read(message_id: message_id)
      end

      def upload_file(channel_id:, io:, filename:, thread_id: nil, comment: nil) # rubocop:disable Lint/UnusedMethodArgument
        content_type = detect_content_type(filename)
        media_type = media_type_for(content_type)

        # Upload media first
        media_result = @client.upload_media(io: io, filename: filename, content_type: content_type)
        media_id = media_result["id"]

        # Send media message
        media_payload = {caption: comment}.compact
        result = @client.send_message(to: channel_id, type: media_type, **{media_type => media_payload.merge(id: media_id)})

        parse_whatsapp_message(result, channel_id)
      end

      def add_reaction(channel_id:, message_id:, emoji:)
        @client.send_reaction(to: channel_id, message_id: message_id, emoji: emoji)
      end

      def remove_reaction(channel_id:, message_id:, emoji: "") # rubocop:disable Lint/UnusedMethodArgument
        @client.send_reaction(to: channel_id, message_id: message_id, emoji: "")
      end

      def open_dm(user_id)
        user_id
      end

      def mention(user_id)
        user_id
      end

      def render(postable_message)
        if postable_message.card?
          @renderer.render(postable_message.card)
        else
          postable_message.text
        end
      end

      WHATSAPP_MESSAGE_LIMIT = 4096

      private

      def split_message(text)
        return [text] if text.length <= WHATSAPP_MESSAGE_LIMIT

        chunks = []
        remaining = text
        while remaining.length > WHATSAPP_MESSAGE_LIMIT
          cut_at = remaining.rindex("\n\n", WHATSAPP_MESSAGE_LIMIT) ||
            remaining.rindex("\n", WHATSAPP_MESSAGE_LIMIT) ||
            WHATSAPP_MESSAGE_LIMIT
          chunks << remaining[0...cut_at]
          remaining = remaining[cut_at..].lstrip
        end
        chunks << remaining unless remaining.empty?
        chunks
      end

      def prepare_message_payload(message)
        msg = ChatSDK::PostableMessage.from(message)

        if msg.card?
          rendered = @renderer.render(msg.card)
          if rendered.is_a?(Hash) && rendered[:type] == "interactive"
            {type: "interactive", interactive: rendered[:interactive]}
          else
            {type: "text", text: {body: rendered[:text] || msg.text || msg.card.fallback_text || ""}}
          end
        else
          {type: "text", text: {body: msg.text || ""}}
        end
      end

      def parse_whatsapp_message(data, channel_id)
        message_id = data.dig("messages", 0, "id")

        ChatSDK::Message.new(
          id: message_id,
          text: "",
          author: ChatSDK::Author.new(
            id: "bot",
            name: "bot",
            platform: :whatsapp,
            bot: true
          ),
          thread_id: "whatsapp:#{@phone_number_id}:#{channel_id}",
          channel_id: channel_id,
          platform: :whatsapp,
          raw: data
        )
      end

      CONTENT_TYPES = {
        ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".png" => "image/png",
        ".gif" => "image/gif", ".webp" => "image/webp",
        ".mp4" => "video/mp4", ".3gp" => "video/3gpp",
        ".mp3" => "audio/mpeg", ".ogg" => "audio/ogg", ".amr" => "audio/amr",
        ".pdf" => "application/pdf", ".doc" => "application/msword",
        ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ".xls" => "application/vnd.ms-excel",
        ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      }.freeze

      def detect_content_type(filename)
        CONTENT_TYPES.fetch(File.extname(filename).downcase, "application/octet-stream")
      end

      def media_type_for(content_type)
        case content_type
        when %r{^image/} then "image"
        when %r{^video/} then "video"
        when %r{^audio/} then "audio"
        else "document"
        end
      end
    end
  end
end
