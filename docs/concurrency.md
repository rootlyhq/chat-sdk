# Concurrency

ChatSDK is designed to handle concurrent events safely, even across multiple processes. It uses per-thread locking, queueing, and event deduplication to prevent race conditions.

## Strategies

Configure how overlapping messages on the same thread are handled with `concurrency`:

| Strategy | Behavior |
|----------|----------|
| `:drop` | Process the first message and discard overlapping messages (default) |
| `:force` | Replace the existing lock and process immediately |
| `:queue` | Process the first message, then collapse pending messages into the latest one |
| `:debounce` | Wait for a quiet period and process only the latest message |
| `:burst` | Collapse messages received during a fixed window into the latest one |
| `:concurrent` | Process messages independently, optionally with a per-thread limit |

```ruby
bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: {slack: slack},
  state: state,
  concurrency: {
    strategy: :queue,
    max_queue_size: 10,
    on_queue_full: :drop_oldest,
    queue_entry_ttl_ms: 90_000,
    max_lock_lifetime_ms: 600_000
  }
)
```

For `:queue`, `:debounce`, and `:burst`, message handlers may accept a third argument. It reports the messages collapsed into the current call:

```ruby
bot.on_new_mention do |thread, message, context|
  skipped = context&.fetch(:skipped, []) || []
  thread.post("Processing #{message.text}; #{skipped.length} earlier messages were combined")
end
```

Use `debounce_ms` to configure the quiet/fixed window. Use `max_concurrent` with `:concurrent`. Set `lock_scope: :channel` to serialize all threads in a channel instead of locking each thread independently.

## Per-Thread Locking

When an event arrives, ChatSDK acquires a lock scoped to the thread (identified by adapter name, channel ID, and thread ID). While the lock is held, other events for the same thread are handled according to the `on_lock_conflict` policy.

```ruby
bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: {slack: slack},
  state: ChatSDK::State::Redis.new,
  on_lock_conflict: :drop # deprecated compatibility option
)
```

### Lock Conflict Policies

| Policy | Behavior |
|--------|----------|
| `:drop` | Silently discard the conflicting event (default) |
| `:force` | Take the lock and process the event |
| `Proc` | Custom logic that returns `:force` or `:drop` |

#### Custom Policy Example

```ruby
bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: { slack: slack },
  state: state,
  on_lock_conflict: ->(thread_key, event) {
    # Always process actions (button clicks), drop concurrent mentions
    event.type == :action ? :force : :drop
  }
)
```

Locks have a 30-second TTL and are renewed while handlers run. Renewal stops after `max_lock_lifetime_ms` so a hung handler cannot retain a lock forever.

## Event Deduplication

Platforms sometimes deliver the same event more than once (retries, network issues). ChatSDK deduplicates events by storing their IDs in the state backend with a configurable TTL.

```ruby
bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: { slack: slack },
  state: state,
  dedupe_ttl: 600  # Ignore duplicate events within 10 minutes (default)
)
```

The deduplication key is derived from the event's message ID (for mention/subscribed_message events) or event_id from the raw payload.

## Multi-Process Safety

For multi-process deployments (multiple dynos, Puma workers, Sidekiq processes), use one of the persistent state backends: `ChatSDK::State::Redis`, `ChatSDK::State::Pg`, or `ChatSDK::State::Mysql`. All three provide atomic operations for locks and deduplication records.

```ruby
state = ChatSDK::State::Redis.new(url: ENV["REDIS_URL"])
# or
state = ChatSDK::State::Pg.new(url: ENV["DATABASE_URL"])
# or
state = ChatSDK::State::Mysql.new(url: ENV["MYSQL_URL"])

bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: { slack: slack },
  state: state
)
```

`State::Memory` is not safe across multiple processes because it stores data in a single Ruby process.

## Lock Owner Identity

Lock owners are identified by `"#{Process.pid}:#{Thread.current.object_id}"`. This means:

- Different processes never share the same owner identity
- Different Ruby threads within the same process have different identities
- A process restart clears stale locks automatically via TTL expiration

## Thread Safety Within a Process

`State::Memory` uses a `Mutex` to protect all reads and writes. Multiple Ruby threads can safely dispatch events concurrently when using the Memory backend.

`State::Redis` relies on Redis's single-threaded command execution for atomicity. Lock operations use `SET NX PX` and Lua scripts for safe release.
