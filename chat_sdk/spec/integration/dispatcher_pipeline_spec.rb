# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

RSpec.describe "Integration: dispatcher pipeline" do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }

  describe "deduplication" do
    it "processes same event ID only once" do
      bot = ChatSDK::Chat.new(user_name: "bot", adapters: {test: adapter}, state: state, dedupe_ttl: 60)
      count = 0
      bot.on_new_mention { |_t, _m| count += 1 }

      2.times do
        event = ChatSDK::Events::Mention.new(
          message: ChatSDK::Message.new(id: "same-id", text: "hi",
            author: ChatSDK::Author.new(id: "U1", name: "user", platform: :test),
            thread_id: "T1", channel_id: "C1", platform: :test),
          thread_id: "T1", channel_id: "C1", platform: :test, adapter_name: :test
        )
        bot.dispatch(event, adapter_name: :test)
      end

      expect(count).to eq(1)
    end

    it "processes events with different IDs" do
      bot = ChatSDK::Chat.new(user_name: "bot", adapters: {test: adapter}, state: state, dedupe_ttl: 60)
      count = 0
      bot.on_new_mention { |_t, _m| count += 1 }

      %w[id-1 id-2].each do |id|
        event = ChatSDK::Events::Mention.new(
          message: ChatSDK::Message.new(id: id, text: "hi",
            author: ChatSDK::Author.new(id: "U1", name: "user", platform: :test),
            thread_id: "T1", channel_id: "C1", platform: :test),
          thread_id: "T1", channel_id: "C1", platform: :test, adapter_name: :test
        )
        bot.dispatch(event, adapter_name: :test)
      end

      expect(count).to eq(2)
    end
  end

  describe "lock conflict policies" do
    it "drops event under :drop policy when lock held" do
      bot = ChatSDK::Chat.new(user_name: "bot", adapters: {test: adapter}, state: state, on_lock_conflict: :drop)
      count = 0
      bot.on_new_mention { |_t, _m| count += 1 }

      state.acquire_lock("chat_sdk:lock:test:C1:T1", owner: "other-process", ttl: 60)

      event = ChatSDK::Events::Mention.new(
        message: ChatSDK::Message.new(id: "m1", text: "hi",
          author: ChatSDK::Author.new(id: "U1", name: "user", platform: :test),
          thread_id: "T1", channel_id: "C1", platform: :test),
        thread_id: "T1", channel_id: "C1", platform: :test, adapter_name: :test
      )
      bot.dispatch(event, adapter_name: :test)

      expect(count).to eq(0)
    end

    it "forces lock under :force policy" do
      bot = ChatSDK::Chat.new(user_name: "bot", adapters: {test: adapter}, state: state, on_lock_conflict: :force)
      count = 0
      bot.on_new_mention { |_t, _m| count += 1 }

      state.acquire_lock("chat_sdk:lock:test:C1:T1", owner: "other-process", ttl: 60)

      event = ChatSDK::Events::Mention.new(
        message: ChatSDK::Message.new(id: "m2", text: "hi",
          author: ChatSDK::Author.new(id: "U1", name: "user", platform: :test),
          thread_id: "T1", channel_id: "C1", platform: :test),
        thread_id: "T1", channel_id: "C1", platform: :test, adapter_name: :test
      )
      bot.dispatch(event, adapter_name: :test)

      expect(count).to eq(1)
    end

    it "evaluates callable policy" do
      policy_calls = []
      bot = ChatSDK::Chat.new(
        user_name: "bot", adapters: {test: adapter}, state: state,
        on_lock_conflict: ->(thread_key, _event) {
          policy_calls << thread_key
          :force
        }
      )
      count = 0
      bot.on_new_mention { |_t, _m| count += 1 }

      state.acquire_lock("chat_sdk:lock:test:C1:T1", owner: "other-process", ttl: 60)

      event = ChatSDK::Events::Mention.new(
        message: ChatSDK::Message.new(id: "m3", text: "hi",
          author: ChatSDK::Author.new(id: "U1", name: "user", platform: :test),
          thread_id: "T1", channel_id: "C1", platform: :test),
        thread_id: "T1", channel_id: "C1", platform: :test, adapter_name: :test
      )
      bot.dispatch(event, adapter_name: :test)

      expect(count).to eq(1)
      expect(policy_calls).not_to be_empty
    end
  end

  describe "handler error isolation" do
    it "continues processing after handler raises" do
      bot = ChatSDK::Chat.new(user_name: "bot", adapters: {test: adapter}, state: state)
      results = []

      bot.on_new_mention { |_t, _m| raise "boom" }
      bot.on_new_mention { |_t, msg| results << msg.text }

      adapter.simulate_mention(bot, text: "test")

      # Second handler should not fire since both match the same event
      # but the error in first handler is isolated
      expect(results).to eq(["test"])
    end
  end
end
