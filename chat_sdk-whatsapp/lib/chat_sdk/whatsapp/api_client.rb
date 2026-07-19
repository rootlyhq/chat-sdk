# frozen_string_literal: true

module ChatSDK
  module WhatsApp
    class ApiClient
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
        }.merge(stringify_keys(payload))

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

      def connection
        @connection ||= Faraday.new(url: BASE_URL) do |f|
          f.request :json
          f.response :json
          f.adapter :net_http
          f.headers["Authorization"] = "Bearer #{@access_token}"
        end
      end

      def media_connection
        @media_connection ||= Faraday.new(url: BASE_URL) do |f|
          f.request :multipart
          f.response :json
          f.adapter :net_http
          f.headers["Authorization"] = "Bearer #{@access_token}"
        end
      end

      def request(method, path, body = nil)
        response = connection.public_send(method, path) do |req|
          req.body = body if body && method != :get
        end

        handle_response(response)
      end

      def handle_response(response)
        body = response.body

        if response.success?
          return body if body.is_a?(Hash)

          return {}
        end

        if response.status == 429
          raise ChatSDK::RateLimitedError.new(
            "WhatsApp API rate limited",
            retry_after: nil,
            status: response.status,
            body: body,
            adapter_name: :whatsapp
          )
        end

        error_message = body.is_a?(Hash) ? body.dig("error", "message") : response.status
        raise ChatSDK::PlatformError.new(
          "WhatsApp API error: #{error_message}",
          status: response.status,
          body: body,
          adapter_name: :whatsapp
        )
      end

      def stringify_keys(hash)
        hash.transform_keys(&:to_s).transform_values do |v|
          v.is_a?(Hash) ? stringify_keys(v) : v
        end
      end
    end
  end
end
