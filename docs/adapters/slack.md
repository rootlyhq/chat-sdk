# Slack Adapter

The Slack adapter (`chat_sdk-slack`) provides full integration with Slack's Web API and Block Kit.

## Installation

```ruby
# Gemfile
gem "chat_sdk"
gem "chat_sdk-slack"
```

## Configuration

```ruby
require "chat_sdk"
require "chat_sdk/slack"

slack = ChatSDK::Slack::Adapter.new(
  bot_token: ENV["SLACK_BOT_TOKEN"],       # or set SLACK_BOT_TOKEN env var
  signing_secret: ENV["SLACK_SIGNING_SECRET"] # or set SLACK_SIGNING_SECRET env var
)
```

Both parameters fall back to environment variables if not provided.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `SLACK_BOT_TOKEN` | Bot User OAuth Token (starts with `xoxb-`) |
| `SLACK_SIGNING_SECRET` | Signing Secret from your Slack app settings |

## Slack App Setup

1. Go to [api.slack.com/apps](https://api.slack.com/apps) and create a new app.
2. Under **OAuth & Permissions**, add the bot token scopes your app needs:
   - `chat:write` -- Post messages
   - `chat:write.customize` -- Post with custom username/icon
   - `reactions:write` -- Add/remove reactions
   - `reactions:read` -- Read reactions
   - `files:write` -- Upload files
   - `im:history` -- Read DM history
   - `channels:history` -- Read channel history
   - `groups:history` -- Read private channel history
3. Install the app to your workspace and copy the Bot User OAuth Token.
4. Under **Event Subscriptions**, enable events and set the Request URL to your webhook endpoint (e.g., `https://your-app.com/webhooks/slack`).
5. Subscribe to bot events: `app_mention`, `message.im`, `reaction_added`, `reaction_removed`.
6. Under **Interactivity & Shortcuts**, enable interactivity and set the Request URL to the same webhook endpoint.
7. Copy the **Signing Secret** from Basic Information.

## Webhook URL

Your webhook endpoint should be:

```
https://your-domain.com/webhooks/slack
```

Mount it in your Rack app:

```ruby
map "/webhooks/slack" do
  run bot.webhooks[:slack]
end
```

The endpoint handles Slack's URL verification challenge automatically.

## Capabilities

The Slack adapter supports all capabilities:

| Capability | Supported |
|------------|-----------|
| `edit_messages` | Yes |
| `delete_messages` | Yes |
| `ephemeral_messages` | Yes |
| `file_uploads` | Yes |
| `reactions` | Yes |
| `modals` | Yes |
| `typing_indicator` | Yes (declared, no-op) |
| `streaming_edit` | Yes |
| `threads` | Yes |
| `direct_messages` | Yes |
| `message_history` | Yes |

## Direct Client Access

Access the underlying `Slack::Web::Client` for platform-specific API calls:

```ruby
slack_adapter = bot.adapter(:slack)
client = slack_adapter.client

# Any slack-ruby-client method
client.users_info(user: "U12345")
client.conversations_list(types: "public_channel")
```

## Cards Rendering

Cards built with `ChatSDK.card` are rendered as Slack Block Kit JSON. The `BlockKitRenderer` handles the translation automatically.

## Message IDs

Slack uses timestamps (`ts`) as message IDs. The `Message#id` returned from `post` and other methods is the `ts` value (e.g., `"1234567890.123456"`).
