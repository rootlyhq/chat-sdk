# frozen_string_literal: true

module ChatSDK
  module X
    class ApiClient < ChatSDK::ApiClient::Base
      BASE_URL = "https://api.x.com"

      def initialize(access_token)
        @access_token = access_token
      end

      def create_tweet(text:, reply: nil)
        body = {"text" => text}
        body["reply"] = reply if reply
        request(:post, "/2/tweets", body)
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

      def get_dm_events(participant_id:, cursor: nil, limit: 50)
        query = "max_results=#{[limit, 100].min}&dm_event.fields=id,text,sender_id,created_at"
        query += "&pagination_token=#{cursor}" if cursor
        request(:get, "/2/dm_conversations/with/#{participant_id}/dm_events?#{query}")
      end

      private

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
    end
  end
end
