# frozen_string_literal: true

require "uri"

module ChatSDK
  module WhatsApp
    class ApiClient < ChatSDK::ApiClient::Base
      BASE_URL = "https://graph.facebook.com/v25.0"
      MEDIA_HOSTS = %w[fbcdn.net fbsbx.com].freeze
      MEDIA_DOWNLOAD_LIMIT = 25 * 1024 * 1024
      MEDIA_DOWNLOAD_TIMEOUT = 30

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

      def send_template(to:, template_name:, language_code: "en", components: nil)
        body = {
          "messaging_product" => "whatsapp",
          "to" => to,
          "type" => "template",
          "template" => {
            "name" => template_name,
            "language" => {"code" => language_code}
          }
        }
        body["template"]["components"] = components if components
        request(:post, "#{@phone_number_id}/messages", body)
      end

      def mark_as_read(message_id:)
        request(:post, "#{@phone_number_id}/messages", {
          "messaging_product" => "whatsapp",
          "status" => "read",
          "message_id" => message_id
        })
      end

      def get_media_url(media_id:)
        request(:get, media_id.to_s)
      end

      def download_media(url:)
        validate_media_url!(url)
        Faraday.get(url) do |req|
          req.headers["Authorization"] = "Bearer #{@access_token}"
          req.options.timeout = MEDIA_DOWNLOAD_TIMEOUT
        end
          .tap { |response| validate_media_response!(response) }
      end

      def upload_media(io:, filename:, content_type:)
        response = upload_connection.post("#{@phone_number_id}/media") do |req|
          req.body = {
            "messaging_product" => "whatsapp",
            "file" => Faraday::Multipart::FilePart.new(io, content_type, filename),
            "type" => content_type
          }
        end

        handle_response(response)
      end

      private

      def base_url
        BASE_URL
      end

      def adapter_name
        :whatsapp
      end

      def configure_auth(faraday)
        faraday.headers["Authorization"] = "Bearer #{@access_token}"
      end

      def validate_media_url!(url)
        uri = URI.parse(url)
        host = uri.host&.downcase
        graph_origin = URI.parse(BASE_URL)
        trusted_host = host == graph_origin.host || MEDIA_HOSTS.any? { |allowed| host == allowed || host&.end_with?(".#{allowed}") }
        trusted = uri.is_a?(URI::HTTPS) && uri.port == 443 && trusted_host
        return if trusted

        raise ChatSDK::PlatformError.new(
          "Refusing to send the WhatsApp access token to an untrusted media URL",
          adapter_name: :whatsapp
        )
      rescue URI::InvalidURIError
        raise ChatSDK::PlatformError.new("Invalid WhatsApp media URL", adapter_name: :whatsapp)
      end

      def validate_media_response!(response)
        declared_size = response.headers["content-length"]&.to_i
        actual_size = response.body.respond_to?(:bytesize) ? response.body.bytesize : 0
        return if [declared_size, actual_size].compact.max <= MEDIA_DOWNLOAD_LIMIT

        raise ChatSDK::PlatformError.new(
          "WhatsApp media exceeds the 25 MB download limit",
          status: response.status,
          adapter_name: :whatsapp
        )
      end

      def extract_error_message(response)
        body = response.body
        body.is_a?(Hash) ? body.dig("error", "message") : response.status.to_s
      end
    end
  end
end
