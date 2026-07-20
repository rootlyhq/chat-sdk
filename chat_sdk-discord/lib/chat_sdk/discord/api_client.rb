# frozen_string_literal: true

require "erb"

module ChatSDK
  module Discord
    class ApiClient < ChatSDK::ApiClient::Base
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

      # Users
      def get_user(user_id)
        request(:get, "#{API_PREFIX}/users/#{user_id}")
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

      # Typing indicator
      def trigger_typing(channel_id)
        request(:post, "#{API_PREFIX}/channels/#{channel_id}/typing")
      end

      # File upload
      def upload_file(channel_id, io, filename)
        payload = {
          "file[0]" => Faraday::Multipart::FilePart.new(io, "application/octet-stream", filename)
        }

        response = upload_connection.post("#{API_PREFIX}/channels/#{channel_id}/messages", payload)
        handle_response(response)
      end

      private

      def base_url
        BASE_URL
      end

      def adapter_name
        :discord
      end

      def configure_auth(faraday)
        faraday.headers["Authorization"] = "Bot #{@bot_token}"
      end

      def extract_success_body(response)
        response.body
      end

      def extract_retry_after(response)
        body = response.body
        body.is_a?(Hash) ? body["retry_after"]&.to_i : nil
      end

      def extract_error_message(response)
        response.status.to_s
      end
    end
  end
end
