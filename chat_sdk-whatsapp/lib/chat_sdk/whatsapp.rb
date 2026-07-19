# frozen_string_literal: true

require "chat_sdk"
require "faraday"
require "faraday/net_http"
require "zeitwerk"

module ChatSDK
  module WhatsApp
    class << self
      def loader
        @loader ||= begin
          loader = Zeitwerk::Loader.new
          loader.tag = "chat_sdk-whatsapp"
          loader.inflector.inflect("chat_sdk" => "ChatSDK", "whatsapp" => "WhatsApp")
          loader.push_dir("#{__dir__}/whatsapp", namespace: ChatSDK::WhatsApp)
          loader.setup
          loader
        end
      end
    end
  end
end

ChatSDK::WhatsApp.loader
