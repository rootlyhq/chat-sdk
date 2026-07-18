# State Adapters

State adapters provide persistent storage for thread subscriptions, event deduplication, per-thread locks, and arbitrary key-value data. ChatSDK ships two implementations.

## Memory State

`ChatSDK::State::Memory` stores everything in-process using a `Hash` protected by a `Mutex`.

```ruby
state = ChatSDK::State::Memory.new

bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: { slack: slack },
  state: state
)
```

**When to use:**

- Development and testing
- Single-process deployments
- Prototyping

**Limitations:**

- Data is lost when the process restarts
- Does not work across multiple processes, threads in separate processes, or dynos

See [Memory State](adapters/state-memory.md).

## Redis State

`ChatSDK::State::Redis` stores data in Redis using the `redis-client` gem. All operations are atomic.

```ruby
# Add to your Gemfile:
# gem "chat_sdk-state-redis"

require "chat_sdk-state-redis"

state = ChatSDK::State::Redis.new(url: "redis://localhost:6379")

bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: { slack: slack },
  state: state
)
```

**When to use:**

- Production deployments
- Multi-process or multi-dyno setups
- When you need state to survive restarts

See [Redis State](adapters/state-redis.md).

## Lock Policies

When multiple events arrive for the same thread concurrently, ChatSDK acquires a per-thread lock before invoking handlers. The `on_lock_conflict` option controls what happens when a lock is already held.

### :drop (default)

Silently discard the event. The handler does not fire for the conflicting event.

```ruby
bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: { slack: slack },
  state: state,
  on_lock_conflict: :drop
)
```

### :force

Take the lock from the current holder and process the event. Use this when you want the latest event to always win.

```ruby
bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: { slack: slack },
  state: state,
  on_lock_conflict: :force
)
```

### Custom Proc

Pass a proc for fine-grained control. It receives the thread key and event, and must return `:force` or `:drop`.

```ruby
bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: { slack: slack },
  state: state,
  on_lock_conflict: ->(thread_key, event) {
    event.type == :action ? :force : :drop
  }
)
```

## Event Deduplication

ChatSDK automatically deduplicates events using the state backend. When an event arrives, its ID is stored with a TTL. If the same event arrives again within the TTL window, it is silently dropped.

Configure the TTL with `dedupe_ttl` (default: 600 seconds):

```ruby
bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: { slack: slack },
  state: state,
  dedupe_ttl: 300  # 5 minutes
)
```

## TTL State

Use `thread.set_state` and `thread.state` to store arbitrary per-thread data with a 30-day TTL:

```ruby
bot.on_new_mention do |thread, message|
  count = thread.state || { "count" => 0 }
  count["count"] += 1
  thread.set_state(count)
  thread.post("This thread has been mentioned #{count["count"]} times.")
end
```

## Building Custom State Adapters

Subclass `ChatSDK::State::Base` and implement all methods. Use the shared contract examples to verify your implementation:

```ruby
require "chat_sdk/testing/state_contract"

RSpec.describe MyCustomState do
  subject { MyCustomState.new }
  it_behaves_like "a chat_sdk state adapter"
end
```
