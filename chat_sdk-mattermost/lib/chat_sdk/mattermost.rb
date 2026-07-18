# frozen_string_literal: true

require "chat_sdk"
require "faraday"
require "faraday/net_http"
require "zeitwerk"

module ChatSDK
  module Mattermost
    class << self
      def loader
        @loader ||= begin
          loader = Zeitwerk::Loader.new
          loader.tag = "chat_sdk-mattermost"
          loader.inflector.inflect("chat_sdk" => "ChatSDK")
          loader.push_dir("#{__dir__}/mattermost", namespace: ChatSDK::Mattermost)
          loader.setup
          loader
        end
      end
    end
  end
end

ChatSDK::Mattermost.loader
