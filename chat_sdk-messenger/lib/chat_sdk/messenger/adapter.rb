# frozen_string_literal: true

module ChatSDK
  module Messenger
    class Adapter < ChatSDK::Adapter::Base
      include ChatSDK::Adapter::MetaVerification

      capabilities :typing_indicator, :direct_messages, :file_uploads

      attr_reader :client

      def initialize(app_secret: nil, page_access_token: nil, verify_token: nil, page_id: nil)
        @app_secret = app_secret || ENV["FACEBOOK_APP_SECRET"]
        @page_access_token = page_access_token || ENV["FACEBOOK_PAGE_ACCESS_TOKEN"]
        @verify_token = verify_token || ENV["FACEBOOK_VERIFY_TOKEN"]
        @page_id = page_id || ENV["FACEBOOK_PAGE_ID"]

        raise ChatSDK::ConfigurationError, "Messenger app_secret required" unless @app_secret
        raise ChatSDK::ConfigurationError, "Messenger page_access_token required" unless @page_access_token

        @client = ApiClient.new(@page_access_token)
        @renderer = TemplateRenderer.new
      end

      def name
        :messenger
      end

      # Inbound
      def verify_request!(rack_request)
        verify_meta_signature!(rack_request, secret: @app_secret, platform_name: "Facebook")
      end

      def ack_response(rack_request)
        meta_ack_response(rack_request, verify_token: @verify_token)
      end

      def parse_events(rack_request)
        payload = read_json_body(rack_request)
        EventParser.parse(payload, bot_page_id: @page_id)
      rescue JSON::ParserError
        []
      end

      # Outbound
      def post_message(channel_id:, message:, thread_id: nil) # rubocop:disable Lint/UnusedMethodArgument
        payload = prepare_message_payload(message)

        result = @client.send_message(
          recipient_id: channel_id,
          message: payload
        )

        parse_messenger_message(result, channel_id)
      end

      def upload_file(channel_id:, io:, filename:, thread_id: nil, comment: nil) # rubocop:disable Lint/UnusedMethodArgument
        raise ChatSDK::PlatformError.new(
          "Messenger file uploads require a publicly accessible URL. Binary upload is not supported. " \
          "Host the file at a public URL and send it as an attachment.",
          adapter_name: :messenger
        )
      end

      def open_dm(user_id)
        user_id
      end

      def start_typing(channel_id:, thread_id: nil) # rubocop:disable Lint/UnusedMethodArgument
        @client.send_action(recipient_id: channel_id, action: "typing_on")
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

      private

      def prepare_message_payload(message)
        msg = ChatSDK::PostableMessage.from(message)

        if msg.card?
          rendered = @renderer.render(msg.card)
          if rendered.is_a?(Hash) && rendered[:attachment]
            rendered
          else
            {"text" => rendered[:text] || msg.text || msg.card.fallback_text || ""}
          end
        else
          {"text" => msg.text || ""}
        end
      end

      def parse_messenger_message(data, channel_id)
        ChatSDK::Message.new(
          id: data["message_id"],
          text: "",
          author: ChatSDK::Author.new(
            id: "bot",
            name: "bot",
            platform: :messenger,
            bot: true
          ),
          thread_id: "messenger:#{data.dig("recipient_id") || channel_id}",
          channel_id: channel_id,
          platform: :messenger,
          raw: data
        )
      end
    end
  end
end
