# frozen_string_literal: true

module ChatSDK
  module Twilio
    class ApiClient
      BASE_URL = "https://api.twilio.com"

      def initialize(account_sid, auth_token)
        @account_sid = account_sid
        @auth_token = auth_token
      end

      def send_message(to:, body:, from: nil, messaging_service_sid: nil, media_url: nil)
        params = {"To" => to, "Body" => body}
        params["From"] = from if from
        params["MessagingServiceSid"] = messaging_service_sid if messaging_service_sid
        params["MediaUrl"] = media_url if media_url

        response = connection.post(messages_path, URI.encode_www_form(params))
        handle_response(response)
      end

      def send_template(to:, content_sid:, content_variables: nil, from: nil, messaging_service_sid: nil)
        params = {"To" => to, "ContentSid" => content_sid}
        if content_variables
          params["ContentVariables"] = content_variables.is_a?(String) ? content_variables : JSON.generate(content_variables)
        end
        params["From"] = from if from
        params["MessagingServiceSid"] = messaging_service_sid if messaging_service_sid

        response = connection.post(messages_path, URI.encode_www_form(params))
        handle_response(response)
      end

      def start_typing(body:, messaging_api_url: "https://messaging.twilio.com")
        response = messaging_connection(messaging_api_url).post(
          "/v3/Indicators/Typing.json",
          JSON.generate(body)
        )
        handle_response(response)
      end

      def list_messages(to: nil, from: nil, limit: 20)
        params = {"PageSize" => limit.to_s}
        params["To"] = to if to
        params["From"] = from if from
        response = connection.get(messages_path, params)
        handle_response(response)
      end

      def delete_message(message_sid:)
        response = connection.delete("/2010-04-01/Accounts/#{@account_sid}/Messages/#{message_sid}.json")
        return {} if response.status == 204

        handle_response(response)
      end

      private

      def messages_path
        "/2010-04-01/Accounts/#{@account_sid}/Messages.json"
      end

      def connection
        @connection ||= Faraday.new(url: BASE_URL) do |f|
          f.request :authorization, :basic, @account_sid, @auth_token
          f.headers["Content-Type"] = "application/x-www-form-urlencoded"
          f.response :json
          f.adapter :net_http
        end
      end

      def messaging_connection(url)
        Faraday.new(url: url) do |f|
          f.request :authorization, :basic, @account_sid, @auth_token
          f.headers["Content-Type"] = "application/json"
          f.response :json
          f.adapter :net_http
        end
      end

      def handle_response(response)
        body = response.body

        return body if response.success?

        if response.status == 429
          raise ChatSDK::RateLimitedError.new(
            "Twilio API rate limited",
            retry_after: nil,
            status: response.status,
            body: body,
            adapter_name: :twilio
          )
        end

        message = body.is_a?(Hash) ? body["message"] : response.status
        code = body.is_a?(Hash) ? body["code"] : nil
        error = code ? "Twilio API error (#{code}): #{message}" : "Twilio API error: #{message}"
        raise ChatSDK::PlatformError.new(
          error,
          status: response.status,
          body: body,
          adapter_name: :twilio
        )
      end
    end
  end
end
