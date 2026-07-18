# Google Chat Adapter

The Google Chat adapter (`chat_sdk-gchat`) integrates with Google Chat using the Google Chat API and Card v2.

## Installation

```ruby
# Gemfile
gem "chat_sdk"
gem "chat_sdk-gchat"
```

## Configuration

```ruby
require "chat_sdk"
require "chat_sdk/gchat"

gchat = ChatSDK::GChat::Adapter.new(
  project_number: ENV["GOOGLE_CHAT_PROJECT_NUMBER"],
  credentials: nil  # Uses Application Default Credentials
)
```

### Credentials Options

The `credentials` parameter accepts several formats:

```ruby
# 1. nil -- Use Application Default Credentials (ADC)
gchat = ChatSDK::GChat::Adapter.new(project_number: "123456")

# 2. String -- Path to a service account JSON file
gchat = ChatSDK::GChat::Adapter.new(
  project_number: "123456",
  credentials: "/path/to/service-account.json"
)

# 3. Hash -- Service account JSON as a Ruby hash
gchat = ChatSDK::GChat::Adapter.new(
  project_number: "123456",
  credentials: {
    "type" => "service_account",
    "project_id" => "my-project",
    # ...
  }
)

# 4. Pre-built credentials object
gchat = ChatSDK::GChat::Adapter.new(
  project_number: "123456",
  credentials: my_credentials_object
)
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `GOOGLE_CHAT_PROJECT_NUMBER` | Your Google Cloud project number |
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to service account JSON (for ADC) |

## Google Cloud Setup

1. In the [Google Cloud Console](https://console.cloud.google.com), enable the Google Chat API.
2. Create a service account with the Chat Bot scope.
3. Configure your Chat app in the Google Cloud Console:
   - Set the app URL to your webhook endpoint.
   - Configure slash commands if needed.
4. Publish the app to your organization or make it available in Google Workspace Marketplace.

## Webhook URL

```
https://your-domain.com/webhooks/gchat
```

```ruby
map "/webhooks/gchat" do
  run bot.webhooks[:gchat]
end
```

## Capabilities

| Capability | Supported | Notes |
|------------|-----------|-------|
| `edit_messages` | Yes | Uses `update_message` |
| `delete_messages` | Yes | Uses `delete_message` |
| `ephemeral_messages` | Yes | Uses `private_message_viewer` |
| `file_uploads` | No | Raises `NotSupportedError` |
| `reactions` | Yes | Uses unicode emoji |
| `modals` | No | Raises `NotSupportedError` |
| `typing_indicator` | No | Raises `NotSupportedError` |
| `streaming_edit` | Yes | |
| `threads` | Yes | Uses Google Chat thread names |
| `direct_messages` | Yes | Uses `setup_space` with `DIRECT_MESSAGE` |
| `message_history` | Yes | Uses `list_messages` |

## Resource Names

Google Chat uses resource names like `spaces/SPACE_ID/messages/MESSAGE_ID`. ChatSDK extracts the last segment as the ID, so `message.id` returns just `MESSAGE_ID` and `channel_id` is `SPACE_ID`.

## Cards Rendering

Cards are rendered as Google Chat Card v2 JSON using `CardV2Renderer`.

## Mention Formatting

Google Chat uses the format `<users/USER_ID>`:

```ruby
thread.mention_user("12345")  # => "<users/12345>"
```

## Direct Client Access

```ruby
gchat_adapter = bot.adapter(:gchat)
client = gchat_adapter.client  # Google::Apps::Chat::V1::ChatService::Client
```
