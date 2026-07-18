# frozen_string_literal: true

require "zeitwerk"
require_relative "chat_sdk/version"
require_relative "chat_sdk/errors"

module ChatSDK
  class << self
    def loader
      @loader ||= begin
        loader = Zeitwerk::Loader.for_gem(warn_on_extra_files: false)
        loader.inflector.inflect("chat_sdk" => "ChatSDK")
        loader.ignore("#{__dir__}/chat_sdk/version.rb")
        loader.ignore("#{__dir__}/chat_sdk/errors.rb")
        loader.setup
        loader
      end
    end

    def card(title: nil, subtitle: nil, &block)
      Cards::Builder.new(title: title, subtitle: subtitle, &block).build
    end
  end
end

ChatSDK.loader
