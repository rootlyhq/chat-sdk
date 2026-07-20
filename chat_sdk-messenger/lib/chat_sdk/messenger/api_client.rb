# frozen_string_literal: true

module ChatSDK
  module Messenger
    class ApiClient < ChatSDK::ApiClient::Base
      BASE_URL = "https://graph.facebook.com/v25.0/"

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

      def base_url
        BASE_URL
      end

      def adapter_name
        :messenger
      end

      def configure_auth(faraday)
        faraday.params["access_token"] = @page_access_token
      end

      def extract_error_message(response)
        body = response.body
        body.is_a?(Hash) ? body.dig("error", "message") : response.status.to_s
      end
    end
  end
end
