# frozen_string_literal: true

module ChatSDK
  module ApiClient
    class Base
      MAX_RETRIES = 2

      private

      def connection
        @connection ||= build_connection { |f| f.request :json }
      end

      def upload_connection
        @upload_connection ||= build_connection { |f| f.request :multipart }
      end

      def build_connection
        Faraday.new(url: base_url) do |f|
          yield f
          configure_auth(f)
          f.response :json
          f.adapter :net_http
        end
      end

      def base_url
        raise NotImplementedError
      end

      def adapter_name
        raise NotImplementedError
      end

      def configure_auth(faraday)
        raise NotImplementedError
      end

      def request(method, path, body = nil)
        retries = 0
        begin
          response = connection.public_send(method, path) do |req|
            req.body = body if body && method != :get
          end
          handle_response(response)
        rescue ChatSDK::RateLimitedError => e
          retries += 1
          raise if retries > MAX_RETRIES
          sleep(e.retry_after || (2**retries * 0.5))
          retry
        end
      end

      def handle_response(response)
        return extract_success_body(response) if response.success?

        body = response.body

        if response.status == 429
          raise ChatSDK::RateLimitedError.new(
            "#{adapter_name} API rate limited",
            retry_after: extract_retry_after(response),
            status: response.status,
            body: body,
            adapter_name: adapter_name
          )
        end

        raise ChatSDK::PlatformError.new(
          "#{adapter_name} API error: #{extract_error_message(response)}",
          status: response.status,
          body: body,
          adapter_name: adapter_name
        )
      end

      def extract_success_body(response)
        body = response.body
        body.is_a?(Hash) ? body : {}
      end

      def extract_retry_after(_response)
        nil
      end

      def extract_error_message(response)
        response.status.to_s
      end
    end
  end
end
