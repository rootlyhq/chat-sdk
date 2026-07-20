# frozen_string_literal: true

module ChatSDK
  module Teams
    class BotFrameworkClient
      TOKEN_URL = "https://login.microsoftonline.com/botframework.com/oauth2/v2.0/token"
      SCOPE = "https://api.botframework.com/.default"

      attr_reader :app_id, :app_password

      def initialize(app_id:, app_password:)
        @app_id = app_id
        @app_password = app_password
        @access_token = nil
        @token_expires_at = nil
      end

      def send_activity(service_url:, conversation_id:, activity:)
        url = "#{service_url.chomp("/")}/v3/conversations/#{conversation_id}/activities"
        authorized_request(:post, url, activity)
      end

      def update_activity(service_url:, conversation_id:, activity_id:, activity:)
        url = "#{service_url.chomp("/")}/v3/conversations/#{conversation_id}/activities/#{activity_id}"
        authorized_request(:put, url, activity)
      end

      def delete_activity(service_url:, conversation_id:, activity_id:)
        url = "#{service_url.chomp("/")}/v3/conversations/#{conversation_id}/activities/#{activity_id}"
        authorized_request(:delete, url)
      end

      def create_conversation(service_url:, payload:)
        url = "#{service_url.chomp("/")}/v3/conversations"
        authorized_request(:post, url, payload)
      end

      def send_typing(service_url:, conversation_id:)
        activity = {"type" => "typing"}
        send_activity(service_url: service_url, conversation_id: conversation_id, activity: activity)
      end

      def get_conversation_members(service_url:, conversation_id:)
        url = "#{service_url.chomp("/")}/v3/conversations/#{conversation_id}/members"
        authorized_request(:get, url)
      end

      def fetch_token
        return @access_token if @access_token && @token_expires_at && Time.now < @token_expires_at

        response = token_connection.post(TOKEN_URL, {
          grant_type: "client_credentials",
          client_id: @app_id,
          client_secret: @app_password,
          scope: SCOPE
        })

        unless response.success?
          raise ChatSDK::PlatformError.new(
            "Failed to acquire Bot Framework token: #{response.status}",
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

      def authorized_request(method, url, body = nil)
        token = fetch_token

        response = api_connection.public_send(method, url) do |req|
          req.headers["Authorization"] = "Bearer #{token}"
          req.body = body if body && !method.to_s.start_with?("get")
        end

        unless response.success?
          raise ChatSDK::PlatformError.new(
            "Bot Framework API error: #{response.status}",
            status: response.status,
            body: response.body,
            adapter_name: :teams
          )
        end

        response.body
      end
    end
  end
end
