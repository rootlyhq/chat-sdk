# Error Handling

ChatSDK defines a hierarchy of errors that give you precise control over what went wrong and where.

## Error Classes

All ChatSDK errors inherit from `ChatSDK::Error`, which itself inherits from `StandardError`.

```
ChatSDK::Error
  ChatSDK::ConfigurationError
  ChatSDK::NotSupportedError
  ChatSDK::LockConflictError
  ChatSDK::SignatureVerificationError
  ChatSDK::DuplicateEventError
  ChatSDK::PlatformError
    ChatSDK::RateLimitedError
```

## ConfigurationError

Raised when required configuration is missing or invalid.

```ruby
# Missing bot token
ChatSDK::Slack::Adapter.new(bot_token: nil)
# => ChatSDK::ConfigurationError: Slack bot_token required

# Empty user_name
ChatSDK::Chat.new(user_name: "", adapters: {...}, state: state)
# => ChatSDK::ConfigurationError: user_name is required
```

## NotSupportedError

Raised when you call a method that the adapter does not support. Includes the capability name and adapter name.

```ruby
teams = ChatSDK::Teams::Adapter.new(app_id: "...", app_password: "...")
teams.post_ephemeral(channel_id: "C1", user_id: "U1", message: msg)
# => ChatSDK::NotSupportedError: teams adapter does not support ephemeral_messages
```

Handle gracefully:

```ruby
bot.on_new_mention do |thread, message|
  begin
    thread.post_ephemeral("Hint!", user_id: message.author.id)
  rescue ChatSDK::NotSupportedError
    thread.post("Hint!")  # Fallback to regular message
  end
end
```

Check support before calling:

```ruby
if thread.adapter.supports?(:ephemeral_messages)
  thread.post_ephemeral("Secret!", user_id: user_id)
else
  thread.post("Not-so-secret!")
end
```

## PlatformError

Raised when the platform API returns an error. Includes optional `status`, `body`, and `adapter_name`.

```ruby
begin
  thread.post("Hello")
rescue ChatSDK::PlatformError => e
  puts e.message       # "channel_not_found"
  puts e.status        # 404
  puts e.adapter_name  # :slack
end
```

## RateLimitedError

A subclass of `PlatformError` with a `retry_after` attribute indicating how many seconds to wait.

```ruby
begin
  thread.post("Hello")
rescue ChatSDK::RateLimitedError => e
  sleep(e.retry_after || 1)
  retry
end
```

## SignatureVerificationError

Raised by adapters when a webhook request has an invalid or expired signature. ChatSDK webhook endpoints catch this automatically and return a 401 response.

## Handler Errors

Exceptions raised inside event handlers are caught by the dispatcher. ChatSDK logs the full exception and backtrace, then continues to the next handler. The webhook returns 200 for handler failures to avoid platform retries, which could repeat side effects that already ran.

```ruby
bot.on_new_mention do |thread, message|
  raise "Something broke"
end
```

Configure `on_error:` to report handler, webhook, and handler executor failures. The callback receives `(exception, context)`. The context includes `source` (`:handler`, `:webhook`, `:executor` for a callable enqueue failure that returns 500, or `:dispatch` for failures in a `handler_executor: :thread` background dispatch outside a handler), `adapter`, and `event_type`, `thread_id`, and `channel_id` when available. For errors raised before an event is parsed, the event-specific values are absent.

```ruby
bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: {slack: slack},
  state: state,
  on_error: ->(error, context) { ErrorTracker.notify(error, context) }
)
```

When `on_error:` is omitted and Rails is loaded, ChatSDK calls `Rails.error.report(exception, handled: true, severity: :error, context: context)`. Without Rails, failures are logged only. The callback runs after the full exception and backtrace are logged. If the callback raises, ChatSDK logs that failure and does not let it interrupt webhook acknowledgement.

Webhook, handler, and background dispatch errors generally return 200. Platforms retry non-2xx responses, which could repeat side effects that already ran. A callable executor failure is the exception: the webhook returns 500 so the platform redelivers, and the worker deduplicates repeated events. Signature verification failures remain separate and return 401.
