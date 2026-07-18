# frozen_string_literal: true

# config/routes.rb
#
# Mount ChatSDK webhook endpoints in a Rails application.
# Assumes ChatBot.instance is defined in config/initializers/chat_bot.rb
# (see docs/rails.md for the full initializer example).

Rails.application.routes.draw do
  # Single adapter: mount the Slack webhook
  mount ChatBot.instance.webhooks[:slack] => "/webhooks/slack"

  # Multi-adapter: use the router to handle all adapters
  # mount ChatBot.instance.webhooks.router => "/webhooks"
  # This routes /webhooks/slack, /webhooks/teams, /webhooks/gchat
  # based on the last path segment.
end
