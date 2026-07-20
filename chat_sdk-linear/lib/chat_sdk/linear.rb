# frozen_string_literal: true

require "chat_sdk"
require "faraday"
require "faraday/net_http"
require "zeitwerk"

module ChatSDK
  module Linear
    class << self
      def loader
        @loader ||= begin
          loader = Zeitwerk::Loader.new
          loader.tag = "chat_sdk-linear"
          loader.inflector.inflect("chat_sdk" => "ChatSDK", "linear" => "Linear")
          loader.push_dir("#{__dir__}/linear", namespace: ChatSDK::Linear)
          loader.setup
          loader
        end
      end
    end
  end
end

ChatSDK::Linear.loader
