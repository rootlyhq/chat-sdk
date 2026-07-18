# frozen_string_literal: true

module ChatSDK
  module GChat
    module ResourceName
      def extract_id(resource_name)
        return resource_name unless resource_name.is_a?(String)
        resource_name.split("/").last || resource_name
      end
    end
  end
end
