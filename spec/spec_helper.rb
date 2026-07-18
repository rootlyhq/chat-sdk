# frozen_string_literal: true

require "chat_sdk"
require "chat_sdk/testing"
require "webmock/rspec"

ChatSDK::Testing::AdapterContract # rubocop:disable Lint/Void
ChatSDK::Testing::StateContract # rubocop:disable Lint/Void

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.order = :random
  Kernel.srand config.seed
end
