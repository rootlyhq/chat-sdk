# Twilio Adapter

The Twilio adapter (`chat_sdk-twilio`) supports SMS messaging, message history, deletion, Content API templates, and WhatsApp/RCS typing indicators.

## Configuration

```ruby
twilio = ChatSDK::Twilio::Adapter.new(
  account_sid: ENV["TWILIO_ACCOUNT_SID"],
  auth_token: ENV["TWILIO_AUTH_TOKEN"],
  phone_number: ENV["TWILIO_PHONE_NUMBER"],
  messaging_service_sid: ENV["TWILIO_MESSAGING_SERVICE_SID"],
  messaging_api_url: ENV["TWILIO_MESSAGING_API_URL"]
)
```

`messaging_api_url` defaults to `https://messaging.twilio.com` and can be overridden for Messaging v3 typing indicator requests.

## Content templates

Use `send_template` to send a pre-created Twilio Content template:

```ruby
adapter.send_template(
  channel_id: "+15551234567",
  content_sid: "HX123",
  content_variables: {"1" => "Incident update"}
)
```

`content_variables` is JSON-encoded for Twilio. It may be omitted when the template has no variables. The adapter uses the configured `phone_number` or `messaging_service_sid` as the sender.

## Typing indicators

Typing indicators are sent only for WhatsApp or RCS when a `message_id` is available. Other channels and calls without a message ID are no-ops.
