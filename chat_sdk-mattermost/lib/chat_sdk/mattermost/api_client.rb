# frozen_string_literal: true

module ChatSDK
  module Mattermost
    class ApiClient
      attr_reader :base_url

      def initialize(base_url:, bot_token:)
        @base_url = base_url.chomp("/")
        @bot_token = bot_token
      end

      # Posts
      def create_post(channel_id:, message:, root_id: nil, props: nil, file_ids: nil)
        body = {"channel_id" => channel_id, "message" => message}
        body["root_id"] = root_id if root_id
        body["props"] = props if props
        body["file_ids"] = file_ids if file_ids
        request(:post, "/api/v4/posts", body)
      end

      def update_post(post_id:, message:, props: nil)
        body = {"id" => post_id, "message" => message}
        body["props"] = props if props
        request(:put, "/api/v4/posts/#{post_id}", body)
      end

      def delete_post(post_id:)
        request(:delete, "/api/v4/posts/#{post_id}")
      end

      def create_ephemeral_post(user_id:, channel_id:, message:)
        body = {
          "user_id" => user_id,
          "post" => {"channel_id" => channel_id, "message" => message}
        }
        request(:post, "/api/v4/posts/ephemeral", body)
      end

      # Reactions
      def add_reaction(user_id:, post_id:, emoji_name:)
        body = {"user_id" => user_id, "post_id" => post_id, "emoji_name" => emoji_name}
        request(:post, "/api/v4/reactions", body)
      end

      def remove_reaction(user_id:, post_id:, emoji_name:)
        request(:delete, "/api/v4/reactions/#{user_id}/#{post_id}/#{emoji_name}")
      end

      # Channels
      def create_direct_channel(user_ids)
        request(:post, "/api/v4/channels/direct", user_ids)
      end

      def get_channel_posts(channel_id:, page: 0, per_page: 50)
        request(:get, "/api/v4/channels/#{channel_id}/posts?page=#{page}&per_page=#{per_page}")
      end

      # Threads
      def get_post_thread(post_id:)
        request(:get, "/api/v4/posts/#{post_id}/thread")
      end

      # Files
      def upload_file(channel_id:, io:, filename:)
        conn = Faraday.new(url: @base_url) do |f|
          f.request :multipart
          f.response :json
          f.adapter :net_http
        end

        payload = {
          files: Faraday::Multipart::FilePart.new(io, "application/octet-stream", filename),
          channel_id: channel_id
        }

        response = conn.post("/api/v4/files", payload) do |req|
          req.headers["Authorization"] = "Bearer #{@bot_token}"
        end

        handle_response(response)
      end

      # Typing indicator
      def send_typing(channel_id:)
        request(:post, "/api/v4/users/me/typing", {"channel_id" => channel_id})
      end

      private

      def connection
        @connection ||= Faraday.new(url: @base_url) do |f|
          f.request :json
          f.response :json
          f.adapter :net_http
        end
      end

      def request(method, path, body = nil)
        response = connection.public_send(method, path) do |req|
          req.headers["Authorization"] = "Bearer #{@bot_token}"
          req.body = body if body && method != :get
        end

        handle_response(response)
      end

      def handle_response(response)
        return response.body if response.success?

        if response.status == 429
          retry_after = response.headers["Retry-After"]&.to_i
          raise ChatSDK::RateLimitedError.new(
            "Mattermost API rate limited",
            retry_after: retry_after,
            status: response.status,
            body: response.body,
            adapter_name: :mattermost
          )
        end

        raise ChatSDK::PlatformError.new(
          "Mattermost API error: #{response.status}",
          status: response.status,
          body: response.body,
          adapter_name: :mattermost
        )
      end
    end
  end
end
