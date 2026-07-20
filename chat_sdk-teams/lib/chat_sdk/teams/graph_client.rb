# frozen_string_literal: true

module ChatSDK
  module Teams
    class GraphClient
      TOKEN_URL_TEMPLATE = "https://login.microsoftonline.com/%s/oauth2/v2.0/token"
      GRAPH_BASE_URL = "https://graph.microsoft.com/v1.0"
      SCOPE = "https://graph.microsoft.com/.default"

      def initialize(client_id, client_secret, tenant_id)
        @client_id = client_id
        @client_secret = client_secret
        @tenant_id = tenant_id
        @access_token = nil
        @token_expires_at = nil
      end

      def fetch_messages(chat_id:, limit: 50)
        token = fetch_token
        url = "#{GRAPH_BASE_URL}/chats/#{chat_id}/messages?$top=#{limit}&$orderby=createdDateTime desc"

        response = api_connection.get(url) do |req|
          req.headers["Authorization"] = "Bearer #{token}"
        end

        unless response.success?
          raise ChatSDK::PlatformError.new(
            "Graph API error: #{response.status}",
            status: response.status,
            body: response.body,
            adapter_name: :teams
          )
        end

        response.body
      end

      def fetch_token
        return @access_token if @access_token && @token_expires_at && Time.now < @token_expires_at

        token_url = format(TOKEN_URL_TEMPLATE, @tenant_id)

        response = token_connection.post(token_url, {
          grant_type: "client_credentials",
          client_id: @client_id,
          client_secret: @client_secret,
          scope: SCOPE
        })

        unless response.success?
          raise ChatSDK::PlatformError.new(
            "Failed to acquire Graph API token: #{response.status}",
            status: response.status,
            body: response.body,
            adapter_name: :teams
          )
        end

        data = JSON.parse(response.body)
        @access_token = data["access_token"]
        @token_expires_at = Time.now + (data["expires_in"].to_i - 60)
        @access_token
      end

      private

      def token_connection
        @token_connection ||= Faraday.new do |f|
          f.request :url_encoded
          f.adapter :net_http
        end
      end

      def api_connection
        @api_connection ||= Faraday.new do |f|
          f.request :json
          f.response :json
          f.adapter :net_http
        end
      end
    end
  end
end
