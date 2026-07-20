# frozen_string_literal: true

require_relative "../chat_sdk/lib/chat_sdk/version"

Gem::Specification.new do |spec|
  spec.name          = "chat_sdk-gchat"
  spec.version       = ChatSDK::VERSION
  spec.authors       = ["Quentin Rousseau"]
  spec.email         = ["quentin@rootly.com"]
  spec.summary       = "Google Chat adapter for ChatSDK"
  spec.description   = "Google Chat bot adapter for the ChatSDK framework"
  spec.homepage      = "https://github.com/rootlyhq/chat-sdk"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.files         = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]
  spec.add_dependency "chat_sdk", ">= 0.1"
  spec.add_dependency "google-apps-chat-v1"
  spec.add_dependency "googleauth", "~> 1.0"
  spec.metadata["rubygems_mfa_required"] = "true"
end
