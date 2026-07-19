# frozen_string_literal: true

module ChatSDK
  module WhatsApp
    class ApiClient < ChatSDK::ApiClient::Base
      BASE_URL = "https://graph.facebook.com/v21.0"

      def initialize(access_token, phone_number_id)
        @access_token = access_token
        @phone_number_id = phone_number_id
      end

      def send_message(to:, type:, **payload)
        body = {
          "messaging_product" => "whatsapp",
          "recipient_type" => "individual",
          "to" => to,
          "type" => type
        }.merge(payload)

        request(:post, "#{@phone_number_id}/messages", body)
      end

      def send_reaction(to:, message_id:, emoji:)
        send_message(
          to: to,
          type: "reaction",
          reaction: {message_id: message_id, emoji: emoji}
        )
      end

      def upload_media(io:, filename:, content_type:)
        response = media_connection.post("#{@phone_number_id}/media") do |req|
          req.body = {
            "messaging_product" => "whatsapp",
            "file" => Faraday::Multipart::FilePart.new(io, content_type, filename),
            "type" => content_type
          }
        end

        handle_response(response)
      end

      private

      def media_connection
        @media_connection ||= build_connection { |f| f.request :multipart }
      end

      def base_url
        BASE_URL
      end

      def adapter_name
        :whatsapp
      end

      def configure_auth(faraday)
        faraday.headers["Authorization"] = "Bearer #{@access_token}"
      end

      def extract_error_message(response)
        body = response.body
        body.is_a?(Hash) ? body.dig("error", "message") : response.status.to_s
      end
    end
  end
end
