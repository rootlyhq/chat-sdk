# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "chat_sdk/version"

Gem::Specification.new do |spec|
  spec.name          = "chat_sdk"
  spec.version       = ChatSDK::VERSION
  spec.authors       = ["Quentin Rousseau"]
  spec.email         = ["quentin@rootly.com"]
  spec.summary       = "Unified Ruby SDK for building chat bots across Slack, Teams, Google Chat, and more"
  spec.description   = "Platform-agnostic chat bot framework with normalized events, cards DSL, streaming, and pluggable adapters"
  spec.homepage      = "https://github.com/rootlyhq/chat-sdk"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.files         = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]
  spec.add_dependency "commonmarker", "~> 2.0"
  spec.add_dependency "zeitwerk", "~> 2.6"
  spec.metadata["rubygems_mfa_required"] = "true"
end
