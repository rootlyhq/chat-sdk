# frozen_string_literal: true

require "base64"
require "uri"

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

      def fetch_messages(chat_id:, limit: 50, cursor: nil)
        messages_url = chat_messages_url(chat_id)
        url = cursor || "#{messages_url}?$top=#{limit}&$orderby=createdDateTime desc"
        validate_graph_url!(url, chat_id) if cursor
        token = fetch_token

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

      def resolve_reference_attachment(content_url:)
        item = fetch_reference_item(content_url)
        {
          "url" => item["@microsoft.graph.downloadUrl"],
          "mime_type" => item.dig("file", "mimeType") || "application/octet-stream",
          "filename" => item["name"]
        }
      end

      def resolve_reference_url(content_url:)
        resolve_reference_attachment(content_url: content_url).fetch("url")
      end

      def download_reference_attachment(content_url:)
        download_url = resolve_reference_url(content_url: content_url)
        uri = URI.parse(download_url)
        raise ArgumentError, "Teams download URL must use HTTPS" unless uri.is_a?(URI::HTTPS)

        Faraday.get(download_url)
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

      def fetch_reference_item(content_url)
        uri = URI.parse(content_url)
        raise ArgumentError, "Teams attachment URL must use HTTPS" unless uri.is_a?(URI::HTTPS)

        token = fetch_token
        share_id = "u!#{Base64.urlsafe_encode64(content_url, padding: false)}"
        response = api_connection.get("#{GRAPH_BASE_URL}/shares/#{share_id}/driveItem") do |req|
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

        item = response.body
        unless item["@microsoft.graph.downloadUrl"]
          raise ChatSDK::PlatformError.new("Graph API did not return an attachment download URL", adapter_name: :teams)
        end

        item
      rescue URI::InvalidURIError
        raise ArgumentError, "Invalid Teams attachment URL"
      end

      def chat_messages_url(chat_id)
        "#{GRAPH_BASE_URL}/chats/#{URI::DEFAULT_PARSER.escape(chat_id.to_s, /[^A-Za-z0-9._~-]/)}/messages"
      end

      def validate_graph_url!(url, chat_id)
        uri = URI.parse(url)
        expected_path = URI::DEFAULT_PARSER.unescape(URI.parse(chat_messages_url(chat_id)).path)
        actual_path = URI::DEFAULT_PARSER.unescape(uri.path)
        valid = uri.is_a?(URI::HTTPS) && uri.host == "graph.microsoft.com" &&
          uri.port == 443 && !uri.userinfo && !uri.fragment && actual_path == expected_path
        unless valid
          raise ArgumentError,
            "Graph pagination cursor must use https://graph.microsoft.com and the requested chat path"
        end
      rescue URI::InvalidURIError
        raise ArgumentError, "Invalid Graph pagination cursor"
      end
    end
  end
end
