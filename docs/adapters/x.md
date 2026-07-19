# X Adapter

The X adapter (`chat_sdk-x`) integrates with the X (Twitter) API v2 for tweets, direct messages, likes, and HMAC-SHA256 webhook signature verification.

## Installation

```ruby
# Gemfile
gem "chat_sdk"
gem "chat_sdk-x"
```

## Configuration

```ruby
require "chat_sdk"
require "chat_sdk/x"

x = ChatSDK::X::Adapter.new(
  access_token: ENV["X_ACCESS_TOKEN"],         # Bearer token for API v2
  consumer_secret: ENV["X_CONSUMER_SECRET"],   # Consumer secret for webhook verification
  user_id: ENV["X_USER_ID"]                    # Bot user ID (for filtering own messages)
)
```

`access_token` and `consumer_secret` are required. `user_id` is recommended to filter out the bot's own messages from incoming events.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `X_ACCESS_TOKEN` | Bearer token from the X Developer Portal |
| `X_CONSUMER_SECRET` | Consumer secret from your X App settings (for HMAC-SHA256 webhook verification) |
| `X_USER_ID` | The bot's X user ID (used to skip own messages in event parsing) |

## Webhook URL

```
https://your-domain.com/webhooks/x
```

```ruby
map "/webhooks/x" do
  run bot.webhooks[:x]
end
```

## Capabilities

| Capability | Supported |
|------------|-----------|
| `direct_messages` | Yes |
| `reactions` | Yes |
| `edit_messages` | No |
| `delete_messages` | No |
| `ephemeral_messages` | No |
| `typing_indicator` | No |
| `streaming_edit` | No |
| `threads` | No |
| `message_history` | No |
| `file_uploads` | No |

## Direct Client Access

```ruby
x_adapter = bot.adapter(:x)
client = x_adapter.client  # ChatSDK::X::ApiClient
```

## Mention Formatting

```ruby
x_adapter.mention("rootly")  # => "@rootly"
```

## Message IDs

- Tweet IDs are numeric strings (e.g., `"1234567890"`)
- Thread IDs are prefixed: `"x:post:{conversation_id}"` for tweets, `"x:dm:{sender_id}"` for DMs
