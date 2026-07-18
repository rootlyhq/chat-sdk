# frozen_string_literal: true

source "https://rubygems.org"

gem "chat_sdk", path: "chat_sdk"
gem "chat_sdk-slack", path: "chat_sdk-slack"
gem "chat_sdk-teams", path: "chat_sdk-teams"
gem "chat_sdk-gchat", path: "chat_sdk-gchat"
gem "chat_sdk-mattermost", path: "chat_sdk-mattermost"
gem "chat_sdk-state-redis", path: "chat_sdk-state-redis"

group :development, :test do
  gem "rspec", "~> 3.13"
  gem "webmock", "~> 3.23"
  gem "rack-test", "~> 2.1"
  gem "standard", "~> 1.46", require: false
  gem "rubocop-rspec", "~> 3.0", require: false
  gem "standard-performance", "~> 1.7", require: false
  gem "rake", "~> 13.0"
end
