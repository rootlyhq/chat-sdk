# frozen_string_literal: true

require_relative "../chat_sdk/lib/chat_sdk/version"

Gem::Specification.new do |spec|
  spec.name = "chat_sdk-gitlab"
  spec.version = ChatSDK::VERSION
  spec.authors = ["Quentin Rousseau"]
  spec.email = ["quentin@rootly.com"]
  spec.summary = "GitLab adapter for ChatSDK"
  spec.description = "GitLab merge request and issue comment adapter for ChatSDK"
  spec.homepage = "https://github.com/rootlyhq/chat-sdk"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.files = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]
  spec.add_dependency "chat_sdk", ">= 1.2"
  spec.add_dependency "faraday", "~> 2.0"
  spec.metadata["rubygems_mfa_required"] = "true"
end
