# frozen_string_literal: true

require_relative "../chat_sdk/lib/chat_sdk/version"

Gem::Specification.new do |spec|
  spec.name          = "chat_sdk-twilio"
  spec.version       = ChatSDK::VERSION
  spec.authors       = ["Quentin Rousseau"]
  spec.email         = ["quentin@rootly.com"]
  spec.summary       = "Twilio SMS/MMS adapter for ChatSDK"
  spec.description   = "Twilio SMS/MMS adapter for the ChatSDK framework with HMAC-SHA1 signature verification"
  spec.homepage      = "https://github.com/rootlyhq/chat-sdk"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.files         = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]
  spec.add_dependency "chat_sdk", ">= 0.1"
  spec.add_dependency "faraday", "~> 2.0"
  spec.metadata["rubygems_mfa_required"] = "true"
end
