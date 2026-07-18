# frozen_string_literal: true

require_relative "../chat_sdk/lib/chat_sdk/version"

Gem::Specification.new do |spec|
  spec.name          = "chat_sdk-teams"
  spec.version       = ChatSDK::VERSION
  spec.authors       = ["Rootly"]
  spec.email         = ["eng@rootly.com"]
  spec.summary       = "Microsoft Teams adapter for ChatSDK"
  spec.description   = "Microsoft Teams bot adapter for the ChatSDK framework"
  spec.homepage      = "https://github.com/rootlyhq/rootly-chat-sdk"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.files         = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]
  spec.add_dependency "chat_sdk", "~> 0.1"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "jwt", "~> 2.7"
  spec.metadata["rubygems_mfa_required"] = "true"
end
