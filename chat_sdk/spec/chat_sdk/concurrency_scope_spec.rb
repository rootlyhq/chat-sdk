# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

RSpec.describe "adapter concurrency scopes" do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }

  it "isolates deduplication and locks by adapter-provided scope" do
    adapter.define_singleton_method(:concurrency_scope) { |event| event.raw["team_id"] }
    chat = ChatSDK::Chat.new(
      user_name: "test-bot",
      adapters: {test: adapter},
      state: state,
      on_lock_conflict: :drop
    )
    calls = 0
    chat.on_new_mention { |_thread, _message| calls += 1 }

    locked_event = build_event(team_id: "W1", message_id: "M1")
    state.acquire_lock("chat_sdk:lock:test:W1:C1:T1", owner: "other", ttl: 30)
    chat.dispatch(locked_event, adapter_name: :test)
    chat.dispatch(build_event(team_id: "W2", message_id: "M1"), adapter_name: :test)

    expect(calls).to eq(1)
  end

  def build_event(team_id:, message_id:)
    message = ChatSDK::Message.new(
      id: message_id,
      text: "hello",
      author: ChatSDK::Author.new(id: "U1", name: "user", platform: :test),
      thread_id: "T1",
      channel_id: "C1",
      platform: :test
    )
    ChatSDK::Events::Mention.new(
      message: message,
      thread_id: "T1",
      channel_id: "C1",
      platform: :test,
      adapter_name: :test,
      raw: {"team_id" => team_id}
    )
  end
end
