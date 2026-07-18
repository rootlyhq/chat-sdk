# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

RSpec.describe ChatSDK::Dispatcher do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }

  def build_bot(**options)
    ChatSDK::Chat.new(user_name: "test-bot", adapters: {test: adapter}, state: state, **options)
  end

  def make_mention(text: "hello", message_id: "evt_#{rand(10000..99999)}", thread_id: "T1", channel_id: "C1")
    author = ChatSDK::Author.new(id: "U1", name: "user", platform: :test)
    message = ChatSDK::Message.new(
      id: message_id,
      text: text,
      author: author,
      thread_id: thread_id,
      channel_id: channel_id,
      platform: :test
    )
    ChatSDK::Events::Mention.new(
      message: message,
      thread_id: thread_id,
      channel_id: channel_id,
      platform: :test,
      adapter_name: :test
    )
  end

  def make_reaction(emoji: "fire", message_id: "M1", thread_id: "T1", channel_id: "C1")
    ChatSDK::Events::Reaction.new(
      emoji: emoji,
      user_id: "U1",
      message_id: message_id,
      thread_id: thread_id,
      channel_id: channel_id,
      platform: :test,
      adapter_name: :test
    )
  end

  describe "deduplication" do
    it "fires handler once for duplicate events" do
      bot = build_bot
      call_count = 0
      bot.on_new_mention { |_t, _m| call_count += 1 }

      event = make_mention(message_id: "msg_dup_1")
      bot.dispatch(event, adapter_name: :test)
      bot.dispatch(event, adapter_name: :test)

      expect(call_count).to eq(1)
    end

    it "fires handler for events with different IDs" do
      bot = build_bot
      call_count = 0
      bot.on_new_mention { |_t, _m| call_count += 1 }

      bot.dispatch(make_mention(message_id: "msg_a"), adapter_name: :test)
      bot.dispatch(make_mention(message_id: "msg_b"), adapter_name: :test)

      expect(call_count).to eq(2)
    end

    it "allows re-processing after dedupe TTL expires" do
      bot = build_bot(dedupe_ttl: 0)
      call_count = 0
      bot.on_new_mention { |_t, _m| call_count += 1 }

      event = make_mention(message_id: "msg_ttl")
      bot.dispatch(event, adapter_name: :test)
      # TTL=0 means the key expires immediately on next check
      sleep 0.01
      bot.dispatch(event, adapter_name: :test)

      expect(call_count).to eq(2)
    end
  end

  describe "lock conflict :drop" do
    it "drops event when lock is held by another owner" do
      bot = build_bot(on_lock_conflict: :drop)
      call_count = 0
      bot.on_new_mention { |_t, _m| call_count += 1 }

      # Pre-acquire lock with a different owner
      thread_key = "test:C1:T1"
      state.acquire_lock("chat_sdk:lock:#{thread_key}", owner: "other_owner", ttl: 30)

      bot.dispatch(make_mention(message_id: "msg_drop"), adapter_name: :test)

      expect(call_count).to eq(0)
    end
  end

  describe "lock conflict :force" do
    it "forces lock and fires handler when lock is held" do
      bot = build_bot(on_lock_conflict: :force)
      call_count = 0
      bot.on_new_mention { |_t, _m| call_count += 1 }

      thread_key = "test:C1:T1"
      state.acquire_lock("chat_sdk:lock:#{thread_key}", owner: "other_owner", ttl: 30)

      bot.dispatch(make_mention(message_id: "msg_force"), adapter_name: :test)

      expect(call_count).to eq(1)
    end
  end

  describe "lock conflict callable" do
    it "fires handler when callable returns :force" do
      policy = ->(_thread_key, _event) { :force }
      bot = build_bot(on_lock_conflict: policy)
      call_count = 0
      bot.on_new_mention { |_t, _m| call_count += 1 }

      thread_key = "test:C1:T1"
      state.acquire_lock("chat_sdk:lock:#{thread_key}", owner: "other_owner", ttl: 30)

      bot.dispatch(make_mention(message_id: "msg_callable_force"), adapter_name: :test)

      expect(call_count).to eq(1)
    end

    it "drops event when callable returns :drop" do
      policy = ->(_thread_key, _event) { :drop }
      bot = build_bot(on_lock_conflict: policy)
      call_count = 0
      bot.on_new_mention { |_t, _m| call_count += 1 }

      thread_key = "test:C1:T1"
      state.acquire_lock("chat_sdk:lock:#{thread_key}", owner: "other_owner", ttl: 30)

      bot.dispatch(make_mention(message_id: "msg_callable_drop"), adapter_name: :test)

      expect(call_count).to eq(0)
    end
  end

  describe "lock release" do
    it "releases lock after handler completes" do
      bot = build_bot
      bot.on_new_mention { |_t, _m| nil }

      bot.dispatch(make_mention(message_id: "msg_release"), adapter_name: :test)

      thread_key = "test:C1:T1"
      lock_key = "chat_sdk:lock:#{thread_key}"
      # Lock should be released; another acquire should succeed
      expect(state.acquire_lock(lock_key, owner: "new_owner", ttl: 30)).to be true
    end

    it "releases lock even when handler raises" do
      bot = build_bot
      bot.on_new_mention { |_t, _m| raise "boom" }

      bot.dispatch(make_mention(message_id: "msg_err_release"), adapter_name: :test)

      thread_key = "test:C1:T1"
      lock_key = "chat_sdk:lock:#{thread_key}"
      expect(state.acquire_lock(lock_key, owner: "new_owner", ttl: 30)).to be true
    end
  end

  describe "handler error" do
    it "logs error and does not propagate exception" do
      bot = build_bot
      bot.on_new_mention { |_t, _m| raise "handler kaboom" }

      expect {
        bot.dispatch(make_mention(message_id: "msg_err"), adapter_name: :test)
      }.not_to raise_error
    end

    it "continues to next handler after error" do
      bot = build_bot
      second_called = false
      bot.on_new_mention { |_t, _m| raise "first handler fails" }
      bot.on_new_mention { |_t, _m| second_called = true }

      bot.dispatch(make_mention(message_id: "msg_multi_err"), adapter_name: :test)

      expect(second_called).to be true
    end
  end

  describe "event routing" do
    it "routes mention events to on_new_mention handlers" do
      bot = build_bot
      received_text = nil
      bot.on_new_mention { |_t, msg| received_text = msg.text }

      bot.dispatch(make_mention(text: "routed mention", message_id: "msg_route_mention"), adapter_name: :test)

      expect(received_text).to eq("routed mention")
    end

    it "routes reaction events to on_reaction handlers" do
      bot = build_bot
      received_emoji = nil
      bot.on_reaction(%w[fire]) { |event| received_emoji = event.emoji }

      bot.dispatch(make_reaction(emoji: "fire"), adapter_name: :test)

      expect(received_emoji).to eq("fire")
    end

    it "provides thread object to mention handlers" do
      bot = build_bot
      received_thread = nil
      bot.on_new_mention { |thread, _msg| received_thread = thread }

      bot.dispatch(make_mention(message_id: "msg_thread"), adapter_name: :test)

      expect(received_thread).to be_a(ChatSDK::Thread)
      expect(received_thread.id).to eq("T1")
      expect(received_thread.channel_id).to eq("C1")
    end

    it "attaches thread to reaction events" do
      bot = build_bot
      received_thread = nil
      bot.on_reaction(%w[thumbsup]) { |event| received_thread = event.thread }

      bot.dispatch(make_reaction(emoji: "thumbsup"), adapter_name: :test)

      expect(received_thread).to be_a(ChatSDK::Thread)
    end
  end
end
