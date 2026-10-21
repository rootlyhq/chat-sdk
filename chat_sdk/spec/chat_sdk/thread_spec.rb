# frozen_string_literal: true

require_relative "../../../spec/spec_helper"
require "chat_sdk/testing"

RSpec.describe ChatSDK::Thread do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }
  let(:bot) { ChatSDK::Chat.new(user_name: "test-bot", adapters: {test: adapter}, state: state) }
  let(:thread) { described_class.new(id: "T123", channel_id: "C123", adapter: adapter, chat: bot) }

  describe "#subscribe / #subscribed?" do
    it "subscribes and checks" do
      thread.subscribe
      expect(thread.subscribed?).to be true
    end

    it "unsubscribes" do
      thread.subscribe
      thread.unsubscribe
      expect(thread.subscribed?).to be false
    end
  end

  describe "#post" do
    it "posts a string message" do
      thread.post("hello")
      expect(adapter.posted_messages.size).to eq(1)
      expect(adapter.posted_messages.first[:message].text).to eq("hello")
    end

    it "posts a card" do
      card = ChatSDK.card(title: "Test") { text "body" }
      thread.post(card)
      expect(adapter.posted_messages.size).to eq(1)
      expect(adapter.posted_messages.first[:message].card?).to be true
    end

    it "posts a StreamingPlan through the adapter hook and returns its message" do
      message = ChatSDK::Message.new(
        id: "native-1", text: "hello", author: nil, thread_id: "T123",
        channel_id: "C123", platform: :test
      )
      allow(adapter).to receive(:stream) do |channel_id:, thread_id:, stream:, options:|
        expect(channel_id).to eq("C123")
        expect(thread_id).to eq("T123")
        expect(stream.to_a).to eq(["hello"])
        expect(options[:task_display_mode]).to eq("plan")
        message
      end

      result = thread.post(ChatSDK::StreamingPlan.new(["hello"], group_tasks: :plan))

      expect(result).to be(message)
    end
  end

  describe "#post_stream" do
    it "runs the block once when the adapter handles the stream" do
      message = ChatSDK::Message.new(
        id: "native-1", text: "hello", author: nil, thread_id: "T123",
        channel_id: "C123", platform: :test
      )
      block_calls = 0
      allow(adapter).to receive(:stream) do |stream:, **|
        stream.each { |_chunk| }
        message
      end

      result = thread.post_stream do |writer|
        block_calls += 1
        writer << "hello"
      end

      expect(result).to be(message)
      expect(block_calls).to eq(1)
    end

    it "preserves the legacy push-block and placeholder call shape" do
      result = thread.post_stream(placeholder: "Thinking...") do |stream|
        stream << "done"
      end

      expect(result).to be_a(ChatSDK::Message)
      expect(adapter.posted_messages.first[:message].text).to eq("Thinking...")
      expect(adapter.edited_messages.last[:message].text).to eq("done")
    end

    it "runs the block once and uses the core fallback when the adapter returns nil" do
      block_calls = 0
      allow(adapter).to receive(:stream).and_return(nil)

      result = thread.post_stream do |writer|
        block_calls += 1
        writer << "hello "
        writer << ChatSDK::Streaming::TaskUpdateChunk.new(id: "task-1", title: "Hidden", status: "pending")
        writer << ChatSDK::Streaming::MarkdownTextChunk.new(text: "world")
      end

      expect(result).to be_a(ChatSDK::Message)
      expect(result.text).to eq("hello world")
      expect(block_calls).to eq(1)
      expect(adapter.edited_messages.last[:message].text).to eq("hello world")
    end

    it "supports adapters that do not implement the stream hook" do
      allow(adapter).to receive(:respond_to?).and_call_original
      allow(adapter).to receive(:respond_to?).with(:stream).and_return(false)

      result = thread.post_stream(["hello"])

      expect(result).to be_a(ChatSDK::Message)
      expect(result.text).to eq("hello")
    end

    it "merges post_stream options with a StreamingPlan" do
      message = ChatSDK::Message.new(
        id: "native-1", text: "hello", author: nil, thread_id: "T123",
        channel_id: "C123", platform: :test
      )
      allow(adapter).to receive(:stream) do |options:, **|
        expect(options).to include(task_display_mode: "plan", stop_blocks: [{type: "context"}])
        message
      end

      result = thread.post_stream(
        ChatSDK::StreamingPlan.new(["hello"], group_tasks: :plan),
        end_with: [{type: "context"}]
      )

      expect(result).to be(message)
    end

    it "passes AI stream options through post_ai_stream" do
      message = ChatSDK::Message.new(
        id: "native-1", text: "hello", author: nil, thread_id: "T123",
        channel_id: "C123", platform: :test
      )
      allow(adapter).to receive(:stream) do |options:, **|
        expect(options[:ai_generated]).to be(true)
        message
      end

      expect(thread.post_ai_stream(["hello"], ai_generated: true)).to be(message)
    end

    it "passes ai_generated through to the fallback postable message" do
      allow(adapter).to receive(:stream).and_return(nil)

      thread.post_stream(["hello"], ai_generated: true)

      expect(adapter.posted_messages.last[:message].ai_generated).to be(true)
    end

    it "derives recipient team IDs from Slack event payload shapes" do
      raw_payloads = [
        {"team_id" => "T1"},
        {"team" => "T2"},
        {"team" => {"id" => "T3"}},
        {"user" => {"team_id" => "T4"}}
      ]

      raw_payloads.each_with_index do |raw, index|
        inbound_message = ChatSDK::Message.new(
          id: "M#{index}",
          text: "hello",
          author: ChatSDK::Author.new(id: "U1", name: "User", platform: :slack),
          thread_id: "T123",
          channel_id: "C123",
          platform: :slack,
          raw: raw
        )
        current_thread = described_class.new(
          id: "T123",
          channel_id: "C123",
          adapter: adapter,
          chat: bot,
          current_message: inbound_message
        )
        allow(adapter).to receive(:stream) do |options:, **|
          expect(options).to include(recipient_user_id: "U1", recipient_team_id: "T#{index + 1}")
          ChatSDK::Message.new(
            id: "native-#{index}",
            text: "reply",
            author: nil,
            thread_id: "T123",
            channel_id: "C123",
            platform: :slack
          )
        end

        current_thread.post_stream(["reply"])
      end
    end
  end

  describe "#reply" do
    it "replies to a specific message" do
      message = ChatSDK::Message.new(
        id: "M123", text: "question", author: nil, thread_id: "T123",
        channel_id: "C123", platform: :test
      )

      thread.reply(message, "answer")

      expect(adapter.replies_sent.first[:message_id]).to eq("M123")
      expect(adapter.replies_sent.first[:message].text).to eq("answer")
    end
  end

  describe "#mark_as_read" do
    it "marks the current inbound message as read" do
      message = ChatSDK::Message.new(
        id: "M123", text: "hello", author: nil, thread_id: "T123",
        channel_id: "C123", platform: :test
      )
      current_thread = described_class.new(
        id: "T123", channel_id: "C123", adapter: adapter, chat: bot,
        current_message: message
      )

      current_thread.mark_as_read

      expect(adapter.read_receipts_sent.first[:message_id]).to eq("M123")
    end
  end

  describe "#start_typing" do
    it "passes the current message ID when available" do
      message = ChatSDK::Message.new(
        id: "M123", text: "hello", author: nil, thread_id: "T123",
        channel_id: "C123", platform: :test
      )
      current_thread = described_class.new(
        id: "T123", channel_id: "C123", adapter: adapter, chat: bot,
        current_message: message
      )

      current_thread.start_typing

      expect(adapter.typing_started.last[:channel_id]).to eq("C123")
      expect(adapter.typing_started.last[:thread_id]).to eq("T123")
      expect(adapter.typing_started.last[:message_id]).to eq("M123")
    end
  end

  describe "mutation adapter compatibility" do
    let(:legacy_adapter) do
      Class.new(ChatSDK::Adapter::Base) do
        attr_reader :calls

        def initialize
          @calls = []
        end

        def name = :legacy
        def client = self

        def edit_message(channel_id:, message_id:, message:)
          calls << {method: :edit_message, channel_id: channel_id, message_id: message_id, message: message}
        end

        def delete_message(channel_id:, message_id:)
          calls << {method: :delete_message, channel_id: channel_id, message_id: message_id}
        end

        def add_reaction(channel_id:, message_id:, emoji:)
          calls << {method: :add_reaction, channel_id: channel_id, message_id: message_id, emoji: emoji}
        end

        def remove_reaction(channel_id:, message_id:, emoji:)
          calls << {method: :remove_reaction, channel_id: channel_id, message_id: message_id, emoji: emoji}
        end
      end.new
    end
    let(:legacy_thread) do
      described_class.new(id: "T123", channel_id: "C123", adapter: legacy_adapter, chat: bot)
    end

    it "omits thread_id for legacy mutation methods" do
      legacy_thread.edit("M1", "updated")
      legacy_thread.delete("M1")
      legacy_thread.react("M1", "sparkles")
      legacy_thread.unreact("M1", "sparkles")

      expect(legacy_adapter.calls.map { |call| call[:method] }).to eq(
        %i[edit_message delete_message add_reaction remove_reaction]
      )
    end

    it "forwards thread_id to adapters that accept it" do
      thread_aware_adapter = Class.new(ChatSDK::Adapter::Base) do
        attr_reader :thread_ids

        def initialize
          @thread_ids = []
        end

        def edit_message(channel_id:, message_id:, message:, thread_id: nil)
          thread_ids << thread_id
        end
      end.new
      thread_aware = described_class.new(id: "T123", channel_id: "C123", adapter: thread_aware_adapter, chat: bot)

      thread_aware.edit("M1", "updated")

      expect(thread_aware_adapter.thread_ids).to eq(["T123"])
    end
  end

  describe "#state / #set_state" do
    it "stores and retrieves state" do
      thread.set_state({count: 1})
      expect(thread.state).to eq({count: 1})
    end
  end

  describe "#mention_user" do
    it "returns platform mention syntax" do
      expect(thread.mention_user("U123")).to eq("<@U123>")
    end
  end

  describe "equality" do
    it "equals thread with same id and channel" do
      other = described_class.new(id: "T123", channel_id: "C123", adapter: adapter, chat: bot)
      expect(thread).to eq(other)
    end
  end
end
