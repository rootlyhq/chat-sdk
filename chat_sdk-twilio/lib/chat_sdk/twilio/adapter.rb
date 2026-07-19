# frozen_string_literal: true

require "rack/utils"

module ChatSDK
  module Twilio
    class Adapter < ChatSDK::Adapter::Base
      capabilities :direct_messages, :file_uploads

      attr_reader :client

      def initialize(account_sid: nil, auth_token: nil, phone_number: nil, messaging_service_sid: nil, webhook_url: nil)
        @account_sid = account_sid || ENV["TWILIO_ACCOUNT_SID"]
        @auth_token = auth_token || ENV["TWILIO_AUTH_TOKEN"]
        @phone_number = phone_number || ENV["TWILIO_PHONE_NUMBER"]
        @messaging_service_sid = messaging_service_sid || ENV["TWILIO_MESSAGING_SERVICE_SID"]
        @webhook_url = webhook_url

        raise ChatSDK::ConfigurationError, "Twilio account_sid required" unless @account_sid
        raise ChatSDK::ConfigurationError, "Twilio auth_token required" unless @auth_token
        raise ChatSDK::ConfigurationError, "Twilio phone_number or messaging_service_sid required" unless @phone_number || @messaging_service_sid

        @client = ApiClient.new(@account_sid, @auth_token)
      end

      def name
        :twilio
      end

      # Inbound
      def verify_request!(rack_request)
        signature = rack_request.get_header("HTTP_X_TWILIO_SIGNATURE")

        unless signature
          raise ChatSDK::SignatureVerificationError, "Missing Twilio signature header"
        end

        body = rack_request.body.read
        rack_request.body.rewind

        params = Rack::Utils.parse_query(body)
        url = @webhook_url || rack_request.url

        Signature.verify!(@auth_token, url, params, signature)
      end

      def ack_response(_rack_request)
        nil
      end

      def parse_events(rack_request)
        body = rack_request.body.read
        rack_request.body.rewind

        params = Rack::Utils.parse_query(body)
        EventParser.parse(params)
      rescue ArgumentError
        []
      end

      # Outbound
      def post_message(channel_id:, message:, thread_id: nil) # rubocop:disable Lint/UnusedMethodArgument
        text = prepare_message_payload(message)

        result = @client.send_message(
          to: channel_id,
          body: text,
          from: @phone_number,
          messaging_service_sid: @messaging_service_sid
        )

        parse_twilio_message(result, channel_id)
      end

      def upload_file(channel_id:, io:, filename:, thread_id: nil, comment: nil) # rubocop:disable Lint/UnusedMethodArgument
        raise ChatSDK::PlatformError.new(
          "Twilio MMS requires a publicly accessible MediaUrl. Binary upload is not supported. " \
          "Host the file at a public URL and send it as a message with the URL included.",
          adapter_name: :twilio
        )
      end

      def open_dm(user_id)
        user_id
      end

      def mention(user_id)
        user_id
      end

      def render(postable_message)
        if postable_message.card?
          Cards::Renderer.new.render(postable_message.card)
        else
          postable_message.text
        end
      end

      private

      def prepare_message_payload(message)
        msg = ChatSDK::PostableMessage.from(message)
        msg.text || msg.card&.fallback_text || ""
      end

      def parse_twilio_message(data, channel_id)
        ChatSDK::Message.new(
          id: data["sid"],
          text: data["body"] || "",
          author: ChatSDK::Author.new(
            id: data["from"] || "bot",
            name: data["from"] || "bot",
            platform: :twilio,
            bot: true
          ),
          thread_id: data["sid"],
          channel_id: channel_id,
          platform: :twilio,
          raw: data
        )
      end
    end
  end
end
