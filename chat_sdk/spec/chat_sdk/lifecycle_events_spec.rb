# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

RSpec.describe "Slack lifecycle events" do
  let(:state) { ChatSDK::State::Memory.new }
  let(:adapter) do
    Class.new(ChatSDK::Adapter::Base) do
      def name = :slack
    end.new
  end
  let(:chat) do
    ChatSDK::Chat.new(user_name: "bot", adapters: {slack: adapter}, state: state)
  end

  def assistant_thread_started(raw: nil)
    ChatSDK::Events::AssistantThreadStarted.new(
      thread_id: "1234.5678",
      channel_id: "D123",
      thread_ts: "1234.5678",
      user_id: "U123",
      platform: :slack,
      adapter_name: :slack,
      raw: raw
    )
  end

  it "ignores unknown assistant context keys" do
    event = ChatSDK::Events::AssistantThreadStarted.new(
      thread_id: "1234.5678",
      channel_id: "D123",
      thread_ts: "1234.5678",
      user_id: "U123",
      context: {channel_id: "C456", new_context_key: "ignored"},
      platform: :slack,
      adapter_name: :slack
    )

    expect(event.context).to eq(ChatSDK::Events::AssistantContext.new(channel_id: "C456"))
  end

  it "coerces nil assistant context to an empty AssistantContext" do
    event = ChatSDK::Events::AssistantThreadStarted.new(
      thread_id: "1234.5678",
      channel_id: "D123",
      thread_ts: "1234.5678",
      user_id: "U123",
      context: nil,
      platform: :slack,
      adapter_name: :slack
    )

    expect(event.context).to eq(ChatSDK::Events::AssistantContext.new)
  end

  it "dispatches assistant thread started events to their handler" do
    event = assistant_thread_started
    received = nil
    chat.on_assistant_thread_started { |value| received = value }

    chat.dispatch(event, adapter_name: :slack)

    expect(received).to be(event)
  end

  it "dispatches assistant context changed events to their handler" do
    event = ChatSDK::Events::AssistantContextChanged.new(
      thread_id: "1234.5678",
      channel_id: "D123",
      thread_ts: "1234.5678",
      user_id: "U123",
      platform: :slack,
      adapter_name: :slack
    )
    received = nil
    chat.on_assistant_context_changed { |value| received = value }

    chat.dispatch(event, adapter_name: :slack)

    expect(received).to be(event)
  end

  it "dispatches App Home opened events to their handler" do
    event = ChatSDK::Events::AppHomeOpened.new(
      user_id: "U123",
      channel_id: "D123",
      tab: "home",
      platform: :slack,
      adapter_name: :slack
    )
    received = nil
    chat.on_app_home_opened { |value| received = value }

    chat.dispatch(event, adapter_name: :slack)

    expect(received).to be(event)
  end

  it "dispatches member joined channel events to their handler" do
    event = ChatSDK::Events::MemberJoinedChannel.new(
      user_id: "U123",
      channel_id: "C123",
      inviter_id: "U456",
      platform: :slack,
      adapter_name: :slack
    )
    received = nil
    chat.on_member_joined_channel { |value| received = value }

    chat.dispatch(event, adapter_name: :slack)

    expect(received).to be(event)
  end

  it "runs multiple handlers for the same lifecycle event" do
    calls = []
    chat.on_assistant_thread_started { calls << :first }
    chat.on_assistant_thread_started { calls << :second }

    chat.dispatch(assistant_thread_started, adapter_name: :slack)

    expect(calls).to eq(%i[first second])
  end

  it "logs handler errors and continues to other handlers" do
    second_called = false
    chat.on_assistant_thread_started { raise "handler failed" }
    chat.on_assistant_thread_started { second_called = true }
    expect(ChatSDK::Log).to receive(:error).with(/Handler error \(assistant_thread_started\).*RuntimeError: handler failed/)

    expect { chat.dispatch(assistant_thread_started, adapter_name: :slack) }.not_to raise_error
    expect(second_called).to be(true)
  end

  it "reports lifecycle handler errors through on_error with event context" do
    error = RuntimeError.new("handler failed")
    reported = nil
    reporting_chat = ChatSDK::Chat.new(
      user_name: "bot",
      adapters: {slack: adapter},
      state: state,
      on_error: ->(reported_error, context) { reported = [reported_error, context] }
    )
    reporting_chat.on_assistant_thread_started { raise error }

    reporting_chat.dispatch(assistant_thread_started, adapter_name: :slack)

    expect(reported).to eq([
      error,
      {
        source: :handler,
        adapter: :slack,
        event_type: :assistant_thread_started,
        thread_id: "1234.5678",
        channel_id: "D123"
      }
    ])
  end

  it "dispatches even when the corresponding thread lock is held" do
    called = false
    chat.on_assistant_thread_started { called = true }
    state.acquire_lock("chat_sdk:lock:slack:D123:1234.5678", owner: "other", ttl: 30)

    chat.dispatch(assistant_thread_started, adapter_name: :slack)

    expect(called).to be(true)
  end

  it "deduplicates repeated lifecycle events with the same raw event ID" do
    called = 0
    event = assistant_thread_started(raw: {"event_id" => "Ev123"})
    chat.on_assistant_thread_started { called += 1 }

    chat.dispatch(event, adapter_name: :slack)
    chat.dispatch(event, adapter_name: :slack)

    expect(called).to eq(1)
  end

  it "dispatches lifecycle events without a raw event ID" do
    called = false
    chat.on_assistant_thread_started { called = true }

    chat.dispatch(assistant_thread_started(raw: {}), adapter_name: :slack)

    expect(called).to be(true)
  end
end
