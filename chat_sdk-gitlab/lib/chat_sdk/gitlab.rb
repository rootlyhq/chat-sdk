# frozen_string_literal: true

require "chat_sdk"
require "faraday"
require "faraday/net_http"
require "rack"
require "zeitwerk"

module ChatSDK
  module GitLab
    class << self
      def loader
        @loader ||= begin
          loader = Zeitwerk::Loader.new
          loader.tag = "chat_sdk-gitlab"
          loader.inflector.inflect("chat_sdk" => "ChatSDK", "gitlab" => "GitLab")
          loader.push_dir("#{__dir__}/gitlab", namespace: ChatSDK::GitLab)
          loader.setup
          loader
        end
      end
    end
  end
end

ChatSDK::GitLab.loader
