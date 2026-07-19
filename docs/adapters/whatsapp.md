# WhatsApp Adapter

The WhatsApp adapter (`chat_sdk-whatsapp`) integrates with the WhatsApp Business Cloud API with HMAC-SHA256 webhook signature verification, interactive button messages, and emoji reactions.

## Installation

```ruby
# Gemfile
gem "chat_sdk"
gem "chat_sdk-whatsapp"
```

## Configuration

```ruby
require "chat_sdk"
require "chat_sdk/whatsapp"

whatsapp = ChatSDK::WhatsApp::Adapter.new(
  access_token: ENV["WHATSAPP_ACCESS_TOKEN"],       # Permanent or temporary access token
  app_secret: ENV["WHATSAPP_APP_SECRET"],            # Facebook App Secret
  phone_number_id: ENV["WHATSAPP_PHONE_NUMBER_ID"],  # WhatsApp Phone Number ID
  verify_token: ENV["WHATSAPP_VERIFY_TOKEN"]         # Webhook verify token
)
```

`access_token` and `phone_number_id` are required. `app_secret` is needed for webhook signature verification. `verify_token` is needed for the webhook verification handshake.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `WHATSAPP_ACCESS_TOKEN` | Permanent or temporary access token from Meta Developer Console |
| `WHATSAPP_APP_SECRET` | Your Facebook App Secret (for webhook signature verification) |
| `WHATSAPP_PHONE_NUMBER_ID` | Phone Number ID from WhatsApp Business settings |
| `WHATSAPP_VERIFY_TOKEN` | Custom token for webhook subscription verification |

## WhatsApp Business Setup

1. Create a [Meta App](https://developers.facebook.com/apps/) in the Developer Console.
2. Add the WhatsApp product to your app.
3. In **WhatsApp > Getting Started**, note your Phone Number ID and generate a temporary access token.
4. In **WhatsApp > Configuration**, set your webhook callback URL and verify token.
5. Subscribe to the `messages` webhook field.
6. Copy your App Secret from **Settings > Basic**.

## Webhook URL

```
https://your-domain.com/webhooks/whatsapp
```

```ruby
map "/webhooks/whatsapp" do
  run bot.webhooks[:whatsapp]
end
```

## Capabilities

| Capability | Supported |
|------------|-----------|
| `direct_messages` | Yes |
| `file_uploads` | Yes |
| `reactions` | Yes |
| `edit_messages` | No |
| `delete_messages` | No |
| `ephemeral_messages` | No |
| `typing_indicator` | No |
| `streaming_edit` | No |
| `threads` | No |
| `message_history` | No |

## Direct Client Access

```ruby
whatsapp_adapter = bot.adapter(:whatsapp)
client = whatsapp_adapter.client  # ApiClient
```

## Cards Rendering

Cards render as WhatsApp interactive button messages (up to 3 reply buttons). Link buttons fall back to plain text.

## Message IDs

WhatsApp message IDs look like `wamid.HBgLMTU1NTEyMzQ1NjcVAgASGBQzRUI`.
