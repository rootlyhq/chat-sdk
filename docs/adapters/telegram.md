# Telegram Adapter

The Telegram adapter (`chat_sdk-telegram`) supports bot webhooks, group mentions, replies, inline keyboards, and MarkdownV2 formatting.

## Configuration

```ruby
telegram = ChatSDK::Telegram::Adapter.new(
  bot_token: ENV["TELEGRAM_BOT_TOKEN"],
  secret_token: ENV["TELEGRAM_WEBHOOK_SECRET_TOKEN"],
  bot_username: ENV["TELEGRAM_BOT_USERNAME"],
  mention_on_reply: false
)
```

Set `mention_on_reply: true` to treat replies to the bot as mentions. Replies to a forum topic's root message remain excluded; explicit replies to other bot messages in a topic count as mentions.

Outbound MarkdownV2 messages are limited to Telegram's 4096-character message limit. Truncation preserves complete links, code spans, and formatting entities.
