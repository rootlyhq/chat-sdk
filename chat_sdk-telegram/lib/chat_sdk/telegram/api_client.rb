# frozen_string_literal: true

module ChatSDK
  module Telegram
    class ApiClient < ChatSDK::ApiClient::Base
      BASE_URL = "https://api.telegram.org"

      def initialize(bot_token)
        @bot_token = bot_token
      end

      def send_message(chat_id:, text:, reply_markup: nil, reply_to_message_id: nil)
        body = {"chat_id" => chat_id, "text" => text, "parse_mode" => "Markdown"}
        body["reply_markup"] = reply_markup if reply_markup
        body["reply_to_message_id"] = reply_to_message_id if reply_to_message_id
        request(:post, "sendMessage", body)
      end

      def edit_message_text(chat_id:, message_id:, text:, reply_markup: nil)
        body = {"chat_id" => chat_id, "message_id" => message_id, "text" => text, "parse_mode" => "Markdown"}
        body["reply_markup"] = reply_markup if reply_markup
        request(:post, "editMessageText", body)
      end

      def delete_message(chat_id:, message_id:)
        request(:post, "deleteMessage", {"chat_id" => chat_id, "message_id" => message_id})
      end

      def send_document(chat_id:, document:, filename:, caption: nil, reply_to_message_id: nil)
        payload = {
          "chat_id" => chat_id,
          "document" => Faraday::Multipart::FilePart.new(document, "application/octet-stream", filename)
        }
        payload["caption"] = caption if caption
        payload["reply_to_message_id"] = reply_to_message_id if reply_to_message_id

        response = upload_connection.post(api_path("sendDocument"), payload)
        handle_response(response)
      end

      def set_message_reaction(chat_id:, message_id:, reaction:)
        request(:post, "setMessageReaction", {
          "chat_id" => chat_id,
          "message_id" => message_id,
          "reaction" => reaction
        })
      end

      def send_chat_action(chat_id:, action:)
        request(:post, "sendChatAction", {"chat_id" => chat_id, "action" => action})
      end

      def get_chat(chat_id:)
        request(:post, "getChat", {"chat_id" => chat_id})
      end

      def get_updates(offset: nil, timeout: 30)
        body = {"timeout" => timeout}
        body["offset"] = offset if offset
        request(:post, "getUpdates", body)
      end

      private

      def api_path(method)
        "/bot#{@bot_token}/#{method}"
      end

      def base_url
        BASE_URL
      end

      def adapter_name
        :telegram
      end

      def configure_auth(_faraday)
        # Telegram uses token in URL path, no auth headers needed
      end

      def resolve_path(path)
        api_path(path)
      end

      def extract_success_body(response)
        body = response.body
        (body.is_a?(Hash) && body["ok"]) ? body["result"] : {}
      end

      def extract_retry_after(response)
        body = response.body
        body.is_a?(Hash) ? body.dig("parameters", "retry_after")&.to_i : nil
      end

      def extract_error_message(response)
        body = response.body
        body.is_a?(Hash) ? body["description"] : response.status.to_s
      end
    end
  end
end
