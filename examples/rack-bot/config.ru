# frozen_string_literal: true

require "chat_sdk"
require "chat_sdk/slack"

# Configure the Slack adapter
# Set SLACK_BOT_TOKEN and SLACK_SIGNING_SECRET environment variables
slack = ChatSDK::Slack::Adapter.new
state = ChatSDK::State::Memory.new

bot = ChatSDK::Chat.new(
  user_name: "rack-bot",
  adapters:  { slack: slack },
  state:     state,
  log_level: :debug
)

# Respond to @-mentions
bot.on_new_mention do |thread, message|
  thread.post("Hello, #{message.author.name}! You said: #{message.text}")
end

# Pattern-matched handler
bot.on_new_message(/deploy/i) do |thread, message|
  card = ChatSDK.card(title: "Deploy Request") do
    text "Requested by #{message.author.name}"
    fields do
      field "Command", message.text
    end
    actions do
      button "Approve", id: "deploy_approve", style: :primary
      button "Reject",  id: "deploy_reject",  style: :danger
    end
  end
  thread.post(card)
end

# Handle button clicks
bot.on_action("deploy_approve") do |event|
  event.thread.post("Deploy approved by #{event.user.name}!")
end

bot.on_action("deploy_reject") do |event|
  event.thread.post("Deploy rejected by #{event.user.name}.")
end

# Mount the Slack webhook
map "/webhooks/slack" do
  run bot.webhooks[:slack]
end
