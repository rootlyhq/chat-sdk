# frozen_string_literal: true

module ChatSDK
  module GChat
    module ResourceName
      MESSAGE_ID_PATTERN = /\A[A-Za-z0-9_.-]+\z/
      SPACE_ID_PATTERN = /\A[A-Za-z0-9_-]+\z/

      def extract_id(resource_name)
        return resource_name unless resource_name.is_a?(String)
        resource_name.split("/").last || resource_name
      end

      def message_resource_name(channel_id, message_id)
        space_id = channel_id.to_s
        unless channel_id.is_a?(String) && SPACE_ID_PATTERN.match?(space_id)
          raise ChatSDK::Error, "Invalid Google Chat space ID: #{channel_id.inspect}"
        end

        unless message_id.is_a?(String)
          raise ChatSDK::Error, "Invalid Google Chat message ID: #{message_id.inspect}"
        end

        space_name = "spaces/#{space_id}"
        prefix = "#{space_name}/messages/"
        message_name = message_id
        message_name = "#{prefix}#{message_name}" if MESSAGE_ID_PATTERN.match?(message_name)

        unless message_name.start_with?(prefix)
          raise ChatSDK::Error, "Invalid Google Chat message ID: #{message_id.inspect}"
        end

        id = message_name.delete_prefix(prefix)
        unless MESSAGE_ID_PATTERN.match?(id) && id != "." && id != ".."
          raise ChatSDK::Error, "Invalid Google Chat message ID: #{message_id.inspect}"
        end

        "#{prefix}#{id}"
      end
    end
  end
end
