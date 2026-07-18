# frozen_string_literal: true

require "chat_sdk"
require "slack-ruby-client"
require "zeitwerk"

module ChatSDK
  module Slack
    class << self
      def loader
        @loader ||= begin
          loader = Zeitwerk::Loader.new
          loader.tag = "chat_sdk-slack"
          loader.inflector.inflect("chat_sdk" => "ChatSDK")
          loader.push_dir("#{__dir__}/slack", namespace: ChatSDK::Slack)
          loader.setup
          loader
        end
      end
    end
  end
end

ChatSDK::Slack.loader
