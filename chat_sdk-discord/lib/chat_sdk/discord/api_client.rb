# frozen_string_literal: true

require "erb"

module ChatSDK
  module Discord
    class ApiClient
      BASE_URL = "https://discord.com"
      API_PREFIX = "/api/v10"

      def initialize(bot_token:)
        @bot_token = bot_token
      end

      # Messages
      def create_message(channel_id, content: nil, embeds: nil, components: nil)
        body = {}
        body["content"] = content if content
        body["embeds"] = embeds if embeds
        body["components"] = components if components
        request(:post, "#{API_PREFIX}/channels/#{channel_id}/messages", body)
      end

      def edit_message(channel_id, message_id, content: nil, embeds: nil, components: nil)
        body = {}
        body["content"] = content if content
        body["embeds"] = embeds if embeds
        body["components"] = components if components
        request(:patch, "#{API_PREFIX}/channels/#{channel_id}/messages/#{message_id}", body)
      end

      def delete_message(channel_id, message_id)
        request(:delete, "#{API_PREFIX}/channels/#{channel_id}/messages/#{message_id}")
      end

      # Reactions
      def add_reaction(channel_id, message_id, emoji)
        encoded = ERB::Util.url_encode(emoji)
        request(:put, "#{API_PREFIX}/channels/#{channel_id}/messages/#{message_id}/reactions/#{encoded}/@me")
      end

      def remove_reaction(channel_id, message_id, emoji)
        encoded = ERB::Util.url_encode(emoji)
        request(:delete, "#{API_PREFIX}/channels/#{channel_id}/messages/#{message_id}/reactions/#{encoded}/@me")
      end

      # DMs
      def create_dm(user_id)
        request(:post, "#{API_PREFIX}/users/@me/channels", {"recipient_id" => user_id})
      end

      # Messages history
      def get_messages(channel_id, limit: 50, before: nil)
        path = "#{API_PREFIX}/channels/#{channel_id}/messages?limit=#{limit}"
        path += "&before=#{before}" if before
        request(:get, path)
      end

      # File upload
      def upload_file(channel_id, io, filename)
        payload = {
          "file[0]" => Faraday::Multipart::FilePart.new(io, "application/octet-stream", filename)
        }

        response = upload_connection.post("#{API_PREFIX}/channels/#{channel_id}/messages", payload) do |req|
          req.headers["Authorization"] = "Bot #{@bot_token}"
        end

        handle_response(response)
      end

      private

      def connection
        @connection ||= Faraday.new(url: BASE_URL) do |f|
          f.request :json
          f.response :json
          f.adapter :net_http
        end
      end

      def upload_connection
        @upload_connection ||= Faraday.new(url: BASE_URL) do |f|
          f.request :multipart
          f.response :json
          f.adapter :net_http
        end
      end

      def request(method, path, body = nil)
        response = connection.public_send(method, path) do |req|
          req.headers["Authorization"] = "Bot #{@bot_token}"
          req.body = body if body && method != :get
        end

        handle_response(response)
      end

      def handle_response(response)
        return response.body if response.success?

        if response.status == 429
          retry_after = response.body.is_a?(Hash) ? response.body["retry_after"]&.to_i : nil
          raise ChatSDK::RateLimitedError.new(
            "Discord API rate limited",
            retry_after: retry_after,
            status: response.status,
            body: response.body,
            adapter_name: :discord
          )
        end

        raise ChatSDK::PlatformError.new(
          "Discord API error: #{response.status}",
          status: response.status,
          body: response.body,
          adapter_name: :discord
        )
      end
    end
  end
end
