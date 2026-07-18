# frozen_string_literal: true

require "chat_sdk"
require "faraday"
require "faraday/net_http"
require "ed25519"
require "zeitwerk"

module ChatSDK
  module Discord
    class << self
      def loader
        @loader ||= begin
          loader = Zeitwerk::Loader.new
          loader.tag = "chat_sdk-discord"
          loader.inflector.inflect("chat_sdk" => "ChatSDK")
          loader.push_dir("#{__dir__}/discord", namespace: ChatSDK::Discord)
          loader.setup
          loader
        end
      end
    end
  end
end

ChatSDK::Discord.loader
