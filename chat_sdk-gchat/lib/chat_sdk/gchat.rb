# frozen_string_literal: true

require "chat_sdk"
require "google/apps/chat/v1"
require "googleauth"
require "zeitwerk"

module ChatSDK
  module GChat
    class << self
      def loader
        @loader ||= begin
          loader = Zeitwerk::Loader.new
          loader.tag = "chat_sdk-gchat"
          loader.inflector.inflect("chat_sdk" => "ChatSDK", "gchat" => "GChat")
          loader.push_dir("#{__dir__}/gchat", namespace: ChatSDK::GChat)
          loader.setup
          loader
        end
      end
    end
  end
end

ChatSDK::GChat.loader
