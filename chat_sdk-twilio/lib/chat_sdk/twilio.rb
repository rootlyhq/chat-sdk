# frozen_string_literal: true

require "chat_sdk"
require "faraday"
require "faraday/net_http"
require "zeitwerk"

module ChatSDK
  module Twilio
    class << self
      def loader
        @loader ||= begin
          loader = Zeitwerk::Loader.new
          loader.tag = "chat_sdk-twilio"
          loader.inflector.inflect("chat_sdk" => "ChatSDK")
          loader.push_dir("#{__dir__}/twilio", namespace: ChatSDK::Twilio)
          loader.setup
          loader
        end
      end
    end
  end
end

ChatSDK::Twilio.loader
