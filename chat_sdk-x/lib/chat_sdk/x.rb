# frozen_string_literal: true

require "chat_sdk"
require "faraday"
require "faraday/net_http"
require "zeitwerk"

module ChatSDK
  module X
    class << self
      def loader
        @loader ||= begin
          loader = Zeitwerk::Loader.new
          loader.tag = "chat_sdk-x"
          loader.inflector.inflect("chat_sdk" => "ChatSDK", "x" => "X")
          loader.push_dir("#{__dir__}/x", namespace: ChatSDK::X)
          loader.setup
          loader
        end
      end
    end
  end
end

ChatSDK::X.loader
