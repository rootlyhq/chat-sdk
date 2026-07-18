# frozen_string_literal: true

module ChatSDK
  module AI
    class Converter
      ROLE_USER = "user"
      ROLE_ASSISTANT = "assistant"

      class << self
        def to_ai_messages(messages, include_names: false, &transform)
          messages
            .sort_by { |m| m.timestamp || m.id }
            .reject { |m| m.text.nil? || m.text.strip.empty? }
            .filter_map { |m| convert_message(m, include_names: include_names, &transform) }
        end

        private

        def convert_message(message, include_names: false)
          role = message.author&.bot? ? ROLE_ASSISTANT : ROLE_USER

          content = message.text
          if include_names && role == ROLE_USER && message.author
            content = "[#{message.author.name}]: #{content}"
          end

          result = {role: role, content: content}

          if message.attachments&.any?
            parts = [{type: "text", text: content}]
            message.attachments.each do |att|
              parts << attachment_to_part(att)
            end
            result[:content] = parts
          end

          result = yield(result, message) if block_given?
          result
        end

        def attachment_to_part(attachment)
          if attachment.is_a?(Hash)
            mime = attachment[:mime_type] || attachment[:content_type] || "application/octet-stream"
            if mime.start_with?("image/")
              {type: "image", url: attachment[:url], media_type: mime}
            else
              {type: "file", url: attachment[:url], filename: attachment[:filename], media_type: mime}
            end
          else
            {type: "text", text: attachment.to_s}
          end
        end
      end
    end
  end
end
