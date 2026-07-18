# Rails Integration

ChatSDK integrates cleanly with Rails. This guide covers the recommended setup.

## Initializer

Create an initializer that configures your bot as a singleton:

```ruby
# config/initializers/chat_bot.rb
require "chat_sdk"
require "chat_sdk/slack"

module ChatBot
  def self.instance
    @instance ||= build
  end

  private_class_method def self.build
    slack = ChatSDK::Slack::Adapter.new(
      bot_token: Rails.application.credentials.dig(:slack, :bot_token),
      signing_secret: Rails.application.credentials.dig(:slack, :signing_secret)
    )

    state = if Rails.env.production?
      require "chat_sdk-state-redis"
      ChatSDK::State::Redis.new(url: ENV["REDIS_URL"])
    else
      ChatSDK::State::Memory.new
    end

    bot = ChatSDK::Chat.new(
      user_name: "my-bot",
      adapters: { slack: slack },
      state: state,
      log_level: Rails.env.production? ? :info : :debug
    )

    # Register handlers
    bot.on_new_mention do |thread, message|
      thread.post("Hello from Rails, #{message.author.name}!")
    end

    bot.on_action("approve_btn") do |event|
      event.thread.post("Approved!")
    end

    bot
  end
end
```

## Routes

Mount the webhook endpoint in your routes file:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount ChatBot.instance.webhooks[:slack] => "/webhooks/slack"

  # Or, if using multiple adapters:
  # mount ChatBot.instance.webhooks.router => "/webhooks"
end
```

Set your Slack app's Event Subscriptions Request URL to `https://your-app.com/webhooks/slack`.

## Multi-Adapter Setup

If your bot talks to multiple platforms:

```ruby
# config/initializers/chat_bot.rb
slack = ChatSDK::Slack::Adapter.new
teams = ChatSDK::Teams::Adapter.new

bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: { slack: slack, teams: teams },
  state: ChatSDK::State::Redis.new
)
```

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount ChatBot.instance.webhooks.router => "/webhooks"
  # Handles /webhooks/slack and /webhooks/teams
end
```

## Using Rails Credentials

Store secrets in Rails encrypted credentials instead of environment variables:

```yaml
# config/credentials.yml.enc (decrypted)
slack:
  bot_token: xoxb-...
  signing_secret: abc123...
```

```ruby
slack = ChatSDK::Slack::Adapter.new(
  bot_token: Rails.application.credentials.dig(:slack, :bot_token),
  signing_secret: Rails.application.credentials.dig(:slack, :signing_secret)
)
```

## Proactive Messages

To send messages from controllers, jobs, or other non-handler code:

```ruby
class DeployController < ApplicationController
  def create
    bot = ChatBot.instance
    channel = bot.channel(params[:channel_id], adapter_name: :slack)
    channel.post("Deploy started by #{current_user.name}")
    head :ok
  end
end
```

## Background Processing

Event handlers run synchronously in the webhook request. For long-running work, enqueue a job:

```ruby
bot.on_new_mention do |thread, message|
  thread.post("Working on it...")
  GenerateReportJob.perform_later(
    channel_id: message.channel_id,
    thread_id: message.thread_id,
    text: message.text
  )
end
```

```ruby
class GenerateReportJob < ApplicationJob
  def perform(channel_id:, thread_id:, text:)
    bot = ChatBot.instance
    channel = bot.channel(channel_id, adapter_name: :slack)
    thread = channel.thread(thread_id)
    result = ExpensiveService.call(text)
    thread.post(result)
  end
end
```
