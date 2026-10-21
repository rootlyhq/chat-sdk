# frozen_string_literal: true

require "uri"

module ChatSDK
  module GitLab
    class ApiClient < ChatSDK::ApiClient::Base
      MAX_PAGES = 20
      PER_PAGE = 100

      def initialize(token:, api_url:)
        @token = token
        @api_url = api_url.sub(%r{/+\z}, "")
      end

      def current_user
        request(:get, "/user")
      end

      def request_api(method, path, body: nil, query: nil)
        query_string = URI.encode_www_form(query || {})
        request(method.to_sym, query_string.empty? ? path : "#{path}?#{query_string}", body)
      end

      def request_page(path, query:)
        response = connection.get(resolve_path(path)) do |req|
          req.params.update(query)
        end
        handle_response(response)
        [response.body, response.headers["x-next-page"]]
      end

      def request_all(path, query: {})
        results = []
        page = "1"

        MAX_PAGES.times do
          values, next_page = request_page(path, query: query.merge(per_page: PER_PAGE, page: page))
          results.concat(values) if values.is_a?(Array)
          break if next_page.nil? || next_page.empty?

          page = next_page
        end

        results
      end

      private

      def base_url
        "#{@api_url}/"
      end

      def resolve_path(path)
        path.sub(/\A\//, "")
      end

      def adapter_name
        :gitlab
      end

      def configure_auth(faraday)
        faraday.headers["Authorization"] = "Bearer #{@token}"
      end

      def extract_retry_after(response)
        value = response.headers["retry-after"]
        value.to_i if value
      end

      def extract_error_message(response)
        body = response.body
        return response.status.to_s unless body.is_a?(Hash)

        message = body["message"]
        return message if message.is_a?(String)
        if message.is_a?(Hash)
          return message.map do |field, errors|
            "#{field} #{Array(errors).join(", ")}"
          end.join("; ")
        end

        body["error"] || response.status.to_s
      end
    end
  end
end
