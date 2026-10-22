# frozen_string_literal: true

module ChatSDK
  module GChat
    module PubSubPush
      def self.pubsub_push?(payload)
        return false unless payload.is_a?(Hash)

        message = payload["message"]
        message.is_a?(Hash) && message.key?("data") && payload.key?("subscription")
      end
    end
  end
end
