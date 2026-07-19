# frozen_string_literal: true

module ChatSDK
  module Messenger
    class ApiClient
      BASE_URL = "https://graph.facebook.com/v21.0/"

      def initialize(page_access_token)
        @page_access_token = page_access_token
      end

      def send_message(recipient_id:, message:)
        body = {
          "recipient" => {"id" => recipient_id},
          "message" => message
        }
        request(:post, "me/messages", body)
      end

      def send_action(recipient_id:, action:)
        body = {
          "recipient" => {"id" => recipient_id},
          "sender_action" => action
        }
        request(:post, "me/messages", body)
      end

      private

      def connection
        @connection ||= Faraday.new(url: BASE_URL) do |f|
          f.request :json
          f.response :json
          f.adapter :net_http
          f.params["access_token"] = @page_access_token
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
            "Messenger API rate limited",
            retry_after: nil,
            status: response.status,
            body: body,
            adapter_name: :messenger
          )
        end

        error_message = body.is_a?(Hash) ? body.dig("error", "message") : response.status
        raise ChatSDK::PlatformError.new(
          "Messenger API error: #{error_message}",
          status: response.status,
          body: body,
          adapter_name: :messenger
        )
      end
    end
  end
end
