# frozen_string_literal: true

require_relative "../../../spec/spec_helper"
require "json"
require "rack/test"
require "timeout"

RSpec.describe "handler execution" do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }

  def build_bot(adapter_name: :test, **options)
    ChatSDK::Chat.new(
      user_name: "test-bot",
      adapters: {adapter_name => adapter},
      state: ChatSDK::State::Memory.new,
      **options
    )
  end

  def make_mention(id: "evt_1", text: "hello", adapter_name: :test)
    author = ChatSDK::Author.new(id: "U1", name: "user", platform: :test)
    message = ChatSDK::Message.new(
      id: id,
      text: text,
      author: author,
      thread_id: "T1",
      channel_id: "C1",
      platform: :test
    )
    ChatSDK::Events::Mention.new(
      message: message,
      thread_id: "T1",
      channel_id: "C1",
      platform: :test,
      adapter_name: adapter_name
    )
  end

  def make_action(value: "approved", adapter_name: :test)
    ChatSDK::Events::Action.new(
      action_id: "approve",
      value: value,
      user: ChatSDK::Author.new(id: "U1", name: "user", platform: :test),
      thread_id: "T1",
      channel_id: "C1",
      platform: :test,
      adapter_name: adapter_name
    )
  end

  it "runs handlers synchronously with the default inline executor" do
    bot = build_bot
    received_text = nil
    bot.on_new_mention { |_thread, message| received_text = message.text }

    result = bot.dispatch(make_mention, adapter_name: :test)

    expect(bot.config.handler_executor).to eq(:inline)
    expect(received_text).to eq("hello")
    expect(result).to be_nil
  end

  it "enqueues a JSON-safe payload for callable executors without running handlers" do
    payload = nil
    handler_called = false
    bot = build_bot(handler_executor: ->(value) { payload = value })
    bot.on_new_mention { |_thread, _message| handler_called = true }

    result = bot.dispatch(make_mention, adapter_name: :test)

    expect(result).to be_nil
    expect(handler_called).to be(false)
    expect(payload).to be_a(Hash)
    expect(payload["adapter_name"]).to eq("test")
    expect(JSON.parse(JSON.generate(payload))).to eq(payload)
  end

  it "round-trips mention events through JSON and dispatches their original message" do
    payloads = []
    received = []
    bot = build_bot(handler_executor: ->(payload) { payloads << payload })
    bot.on_new_mention { |thread, message| received << [message.text, thread.id] }
    bot.dispatch(make_mention(text: "serialized mention"), adapter_name: :test)

    bot.dispatch_serialized(JSON.parse(JSON.generate(payloads.fetch(0))))

    expect(received).to eq([["serialized mention", "T1"]])
  end

  it "round-trips action events and runs their matching handler" do
    payloads = []
    received = []
    bot = build_bot(handler_executor: ->(payload) { payloads << payload })
    bot.on_action("approve") { |event| received << [event.value, event.thread_id] }
    bot.dispatch(make_action, adapter_name: :test)

    bot.dispatch_serialized(JSON.parse(JSON.generate(payloads.fetch(0))))

    expect(received).to eq([["approved", "T1"]])
  end

  it "dispatches same-second reactions with distinct timestamps after JSON round-trip" do
    payloads = []
    received_timestamps = []
    bot = build_bot(handler_executor: ->(payload) { payloads << payload })
    bot.on_reaction { |event| received_timestamps << event.timestamp.to_f }
    timestamps = [
      Time.iso8601("2026-10-21T18:01:00.100000Z"),
      Time.iso8601("2026-10-21T18:01:00.300000Z")
    ]

    timestamps.each do |event_timestamp|
      event = ChatSDK::Events::Reaction.new(
        emoji: "fire",
        user_id: "U1",
        message_id: "M1",
        thread_id: "T1",
        channel_id: "C1",
        platform: :test,
        adapter_name: :test,
        timestamp: event_timestamp
      )
      bot.dispatch(event, adapter_name: :test)
    end

    expect(payloads.length).to eq(2)
    payloads.each do |payload|
      bot.dispatch_serialized(JSON.parse(JSON.generate(payload)))
    end

    expect(received_timestamps).to eq(timestamps.map(&:to_f))
  end

  it "uses the registered adapter key when dispatching a serialized event" do
    payloads = []
    received = nil
    bot = build_bot(adapter_name: :primary, handler_executor: ->(payload) { payloads << payload })
    bot.on_new_mention { |_thread, message| received = message.text }
    bot.dispatch(make_mention(adapter_name: :event_adapter), adapter_name: :primary)

    expect(payloads.fetch(0)["adapter_name"]).to eq("primary")
    bot.dispatch_serialized(JSON.parse(JSON.generate(payloads.fetch(0))))

    expect(received).to eq("hello")
  end

  it "deduplicates platform retries in the worker, not the web process" do
    payloads = []
    calls = 0
    bot = build_bot(handler_executor: ->(payload) { payloads << payload })
    bot.on_new_mention { |_thread, _message| calls += 1 }
    event = make_mention(id: "retry-event")

    bot.dispatch(event, adapter_name: :test)
    bot.dispatch(event, adapter_name: :test)

    expect(payloads.length).to eq(2)
    payloads.each do |payload|
      bot.dispatch_serialized(JSON.parse(JSON.generate(payload)))
    end

    expect(calls).to eq(1)
  end

  it "does not mark a single enqueued event as a duplicate before worker dispatch" do
    payloads = []
    calls = 0
    bot = build_bot(handler_executor: ->(payload) { payloads << payload })
    bot.on_new_mention { |_thread, _message| calls += 1 }

    bot.dispatch(make_mention(id: "single-event"), adapter_name: :test)
    bot.dispatch_serialized(JSON.parse(JSON.generate(payloads.fetch(0))))

    expect(calls).to eq(1)
  end

  it "reports handler errors from serialized dispatch without raising" do
    reported = []
    bot = build_bot(
      handler_executor: ->(_payload) {},
      on_error: ->(error, context) { reported << [error, context] }
    )
    bot.on_new_mention { |_thread, _message| raise "worker handler failed" }

    expect {
      bot.dispatch_serialized(
        "adapter_name" => "test",
        "event" => ChatSDK::EventSerializer.dump(make_mention)
      )
    }.not_to raise_error

    expect(reported.last.first.message).to eq("worker handler failed")
    expect(reported.last.last).to include(
      source: :handler,
      adapter: :test,
      event_type: :mention,
      thread_id: "T1",
      channel_id: "C1"
    )
  end

  it "propagates non-handler errors from serialized dispatch" do
    bot = build_bot(handler_executor: ->(_payload) {})
    payload = {
      "adapter_name" => "unknown",
      "event" => ChatSDK::EventSerializer.dump(make_mention)
    }

    expect {
      bot.dispatch_serialized(payload)
    }.to raise_error(ChatSDK::ConfigurationError, "Unknown adapter: unknown")
  end

  it "runs handlers on another thread with the thread executor" do
    handler_threads = Queue.new
    bot = build_bot(handler_executor: :thread)
    bot.on_new_mention { |_thread, _message| handler_threads << ::Thread.current }

    bot.dispatch(make_mention, adapter_name: :test)
    handler_thread = Timeout.timeout(2) { handler_threads.pop }
    handler_thread.join

    expect(handler_thread).not_to eq(::Thread.current)
  end

  it "reports background dispatch errors from the thread executor" do
    errors = Queue.new
    bot = build_bot(
      handler_executor: :thread,
      on_error: ->(error, context) { errors << [error, context, ::Thread.current] }
    )
    dispatcher = bot.instance_variable_get(:@dispatcher)
    allow(dispatcher).to receive(:dispatch).and_raise("state outage")

    bot.dispatch(make_mention, adapter_name: :test)
    error, context, worker = Timeout.timeout(2) { errors.pop }
    worker.join

    expect(error.message).to eq("state outage")
    expect(context).to include(
      source: :dispatch,
      adapter: :test,
      event_type: :mention,
      thread_id: "T1",
      channel_id: "C1"
    )
  end

  it "returns 200 without running handlers when an endpoint uses a callable executor" do
    payloads = []
    handler_called = false
    bot = build_bot(handler_executor: ->(payload) { payloads << payload })
    bot.on_new_mention { |_thread, _message| handler_called = true }
    allow(adapter).to receive(:parse_events).and_return([make_mention])
    env = Rack::MockRequest.env_for("/webhook", method: "POST", input: "{}")

    status, = bot.webhooks[:test].call(env)

    expect(status).to eq(200)
    expect(handler_called).to be(false)
    expect(payloads.length).to eq(1)
  end
end
