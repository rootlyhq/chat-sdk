# frozen_string_literal: true

require "chat_sdk"
require "faraday"
require "faraday/net_http"
require "jwt"
require "zeitwerk"

module ChatSDK
  module Teams
    class << self
      def loader
        @loader ||= begin
          loader = Zeitwerk::Loader.new
          loader.tag = "chat_sdk-teams"
          loader.inflector.inflect("chat_sdk" => "ChatSDK")
          loader.push_dir("#{__dir__}/teams", namespace: ChatSDK::Teams)
          loader.setup
          loader
        end
      end
    end
  end
end

ChatSDK::Teams.loader
