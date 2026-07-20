# frozen_string_literal: true

require "base64"

module ChatSDK
  module X
    class ApiClient < ChatSDK::ApiClient::Base
      BASE_URL = "https://api.x.com"
      TOKEN_URL = "https://api.x.com/2/oauth2/token"
      TOKEN_EXPIRY_MARGIN = 60 # seconds before expiry to trigger proactive refresh

      def initialize(access_token: nil, client_id: nil, client_secret: nil,
        refresh_token: nil, state: nil)
        @access_token = access_token
        @client_id = client_id
        @client_secret = client_secret
        @refresh_token = refresh_token
        @state = state
        @token_expires_at = nil
        @refresh_mutex = Mutex.new
      end

      # Allow post-init state injection (called by adapter's set_state)
      attr_writer :state

      def create_tweet(text:, reply_to: nil, media_ids: nil)
        body = {"text" => text}
        body["reply"] = {"in_reply_to_tweet_id" => reply_to} if reply_to
        body["media"] = {"media_ids" => media_ids} if media_ids&.any?
        request(:post, "/2/tweets", body)
      end

      def upload_media(io:, content_type:, total_bytes:)
        # INIT
        init_result = request(:post, "/2/media/upload", {
          command: "INIT",
          total_bytes: total_bytes,
          media_type: content_type
        })
        media_id = init_result.dig("data", "id") || init_result["media_id_string"]

        # APPEND (single chunk, works for images <5MB)
        response = upload_connection.post("/2/media/upload") do |req|
          req.body = {
            command: "APPEND",
            media_id: media_id,
            segment_index: 0,
            media_data: Base64.strict_encode64(io.read)
          }
        end
        handle_response(response)

        # FINALIZE
        request(:post, "/2/media/upload", {
          command: "FINALIZE",
          media_id: media_id
        })

        media_id
      end

      def send_dm(participant_id:, text:)
        request(:post, "/2/dm_conversations/with/#{participant_id}/messages", {"text" => text})
      end

      def like_tweet(user_id:, tweet_id:)
        request(:post, "/2/users/#{user_id}/likes", {"tweet_id" => tweet_id})
      end

      def unlike_tweet(user_id:, tweet_id:)
        request(:delete, "/2/users/#{user_id}/likes/#{tweet_id}")
      end

      def delete_tweet(tweet_id:)
        request(:delete, "/2/tweets/#{tweet_id}")
      end

      def get_user(user_id)
        request(:get, "/2/users/#{user_id}?user.fields=name,username")
      end

      def get_dm_events(participant_id:, cursor: nil, limit: 50)
        query = "max_results=#{[limit, 100].min}&dm_event.fields=id,text,sender_id,created_at"
        query += "&pagination_token=#{cursor}" if cursor
        request(:get, "/2/dm_conversations/with/#{participant_id}/dm_events?#{query}")
      end

      # Load stored token data from state store (survives restarts)
      def load_stored_token
        return unless @state && @client_id

        stored = @state.get(token_state_key)
        return unless stored.is_a?(Hash)

        @access_token = stored["access_token"] if stored["access_token"]
        @refresh_token = stored["refresh_token"] if stored["refresh_token"]
        @token_expires_at = Time.at(stored["expires_at"]) if stored["expires_at"]
        @connection = nil # rebuild connection with loaded token
      end

      private

      def request(method, path, body = nil)
        ensure_valid_token
        super
      end

      def base_url
        BASE_URL
      end

      def adapter_name
        :x
      end

      def configure_auth(faraday)
        faraday.headers["Authorization"] = "Bearer #{@access_token}"
      end

      def extract_error_message(response)
        body = response.body
        return response.status.to_s unless body.is_a?(Hash)

        body.dig("errors", 0, "message") || body["detail"] || response.status.to_s
      end

      def extract_retry_after(response)
        reset = response.headers["x-rate-limit-reset"]
        return nil unless reset

        seconds = reset.to_i - Time.now.to_i
        [seconds, 1].max
      end

      # OAuth2 token refresh support

      def ensure_valid_token
        return unless @client_id # static token mode — no refresh
        return if @token_expires_at && Time.now < @token_expires_at

        @refresh_mutex.synchronize do
          # Double-check after acquiring lock (another thread may have refreshed)
          return if @token_expires_at && Time.now < @token_expires_at

          refresh_access_token
        end
      end

      def refresh_access_token
        params = {
          "grant_type" => "refresh_token",
          "refresh_token" => @refresh_token
        }
        # Public client: client_id in body; Confidential client: Basic auth header
        params["client_id"] = @client_id unless @client_secret

        headers = {"Content-Type" => "application/x-www-form-urlencoded"}
        if @client_secret
          encoded = Base64.strict_encode64("#{@client_id}:#{@client_secret}")
          headers["Authorization"] = "Basic #{encoded}"
        end

        response = Faraday.post(TOKEN_URL) do |req|
          req.headers = headers
          req.body = URI.encode_www_form(params)
        end

        unless response.success?
          data = begin
            JSON.parse(response.body)
          rescue JSON::ParserError
            {}
          end
          raise ChatSDK::PlatformError.new(
            "X token refresh failed: #{data["error_description"] || response.status}",
            status: response.status,
            body: response.body,
            adapter_name: :x
          )
        end

        data = JSON.parse(response.body)
        @access_token = data["access_token"]
        @refresh_token = data["refresh_token"] # ROTATED — must persist
        @token_expires_at = Time.now + (data["expires_in"]&.to_i || 7200) - TOKEN_EXPIRY_MARGIN

        # Rebuild Faraday connection with new token
        @connection = nil

        persist_token
      end

      def token_state_key
        "x:oauth:#{@client_id}"
      end

      def persist_token
        return unless @state

        @state.set(token_state_key, {
          "access_token" => @access_token,
          "refresh_token" => @refresh_token,
          "expires_at" => @token_expires_at&.to_f
        })
      end
    end
  end
end
