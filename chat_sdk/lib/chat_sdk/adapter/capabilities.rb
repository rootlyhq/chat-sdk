# frozen_string_literal: true

module ChatSDK
  module Adapter
    module Capabilities
      KNOWN = %i[
        edit_messages delete_messages ephemeral_messages
        file_uploads reactions modals typing_indicator
        streaming_edit threads direct_messages
        scheduled_messages message_history
      ].freeze

      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def capabilities(*caps)
          unknown = caps - KNOWN
          raise ArgumentError, "Unknown capabilities: #{unknown.join(", ")}" if unknown.any?
          @capabilities = caps
        end

        def declared_capabilities
          @capabilities || []
        end
      end

      def supports?(capability)
        self.class.declared_capabilities.include?(capability)
      end
    end
  end
end
