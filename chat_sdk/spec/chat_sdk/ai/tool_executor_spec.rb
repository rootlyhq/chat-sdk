# frozen_string_literal: true

require_relative "../../../../spec/spec_helper"

RSpec.describe ChatSDK::AI::ToolExecutor do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }
  let(:chat) { ChatSDK::Chat.new(user_name: "test-bot", adapters: {test: adapter}, state: state) }
  let(:executor) { described_class.new(chat: chat) }

  describe "#execute" do
    it "raises on unknown tool" do
      expect { executor.execute(:nonexistent, {}) }
        .to raise_error(ChatSDK::Error, /Unknown tool/)
    end

    it "executes post_message" do
      result = executor.execute(:post_message, {adapter_name: "test", channel_id: "C1", text: "hello"})
      expect(result[:text]).to eq("hello")
      expect(result[:id]).to be_a(String)
      expect(adapter.posted_messages.size).to eq(1)
      expect(adapter.posted_messages.last[:message].ai_generated).to be(true)
    end

    it "executes post_message with string keys" do
      result = executor.execute("post_message", {"adapter_name" => "test", "channel_id" => "C1", "text" => "hello"})
      expect(result[:text]).to eq("hello")
    end

    it "executes post_message to thread" do
      result = executor.execute(:post_message, {adapter_name: "test", channel_id: "C1", thread_id: "T1", text: "reply"})
      expect(result[:text]).to eq("reply")
      expect(adapter.posted_messages.last[:thread_id]).to eq("T1")
    end

    it "executes send_direct_message" do
      result = executor.execute(:send_direct_message, {adapter_name: "test", user_id: "U1", text: "hi"})
      expect(result[:channel_id]).to eq("dm_U1")
      expect(adapter.dm_channels.size).to eq(1)
      expect(adapter.posted_messages.last[:message].ai_generated).to be(true)
    end

    it "executes edit_message" do
      result = executor.execute(:edit_message, {adapter_name: "test", channel_id: "C1", message_id: "M1", text: "updated"})
      expect(result[:success]).to be true
      expect(adapter.edited_messages.size).to eq(1)
      expect(adapter.edited_messages.last[:message].ai_generated).to be(true)
    end

    it "executes delete_message" do
      result = executor.execute(:delete_message, {adapter_name: "test", channel_id: "C1", message_id: "M1"})
      expect(result[:success]).to be true
      expect(adapter.deleted_messages.size).to eq(1)
    end

    it "executes add_reaction" do
      result = executor.execute(:add_reaction, {adapter_name: "test", channel_id: "C1", message_id: "M1", emoji: "thumbsup"})
      expect(result[:success]).to be true
      expect(adapter.reactions_added.size).to eq(1)
    end

    it "executes remove_reaction" do
      result = executor.execute(:remove_reaction, {adapter_name: "test", channel_id: "C1", message_id: "M1", emoji: "thumbsup"})
      expect(result[:success]).to be true
      expect(adapter.reactions_removed.size).to eq(1)
    end

    it "executes start_typing" do
      result = executor.execute(:start_typing, {adapter_name: "test", channel_id: "C1"})
      expect(result[:success]).to be true
      expect(adapter.typing_started.size).to eq(1)
    end

    it "uses the handler's current message ID for typing indicators" do
      incoming = ChatSDK::Message.new(
        id: "M_CURRENT", text: "hello",
        author: ChatSDK::Author.new(id: "U1", name: "user", platform: :test),
        thread_id: "T1", channel_id: "C1", platform: :test
      )
      thread = ChatSDK::Thread.new(id: "T1", channel_id: "C1", adapter: adapter, chat: chat, current_message: incoming)

      ChatSDK::AI::ConversationScope.with(thread) do
        executor.execute(:start_typing, {adapter_name: "test", channel_id: "C1", thread_id: "T1"})
      end

      expect(adapter.typing_started.last[:message_id]).to eq("M_CURRENT")
    end

    it "allows direct-message tools inside a conversation handler" do
      thread = ChatSDK::Thread.new(id: "T1", channel_id: "C1", adapter: adapter, chat: chat)

      ChatSDK::AI::ConversationScope.with(thread) do
        executor.execute(:send_direct_message, {adapter_name: "test", user_id: "U1", text: "hello"})
      end

      expect(adapter.dm_channels.size).to eq(1)
    end

    it "resolves an implicit scope when the tool executes" do
      thread = ChatSDK::Thread.new(id: "T1", channel_id: "C1", adapter: adapter, chat: chat)
      scoped_executor = nil

      ChatSDK::AI::ConversationScope.with(thread) do
        scoped_executor = described_class.new(chat: chat)
      end

      allow(ChatSDK::Log).to receive(:warn)
      expect do
        scoped_executor.execute(:fetch_messages, {adapter_name: "test", channel_id: "C2"})
      end.not_to raise_error
      expect(ChatSDK::Log).to have_received(:warn).once
    end

    it "warns once per tool when used outside a handler without a scope" do
      allow(ChatSDK::Log).to receive(:warn)

      2.times { executor.execute(:fetch_messages, {adapter_name: "test", channel_id: "C1"}) }
      executor.execute(:fetch_thread, {adapter_name: "test", channel_id: "C1"})

      expect(ChatSDK::Log).to have_received(:warn).twice
    end

    it "rejects an empty scope ID at executor creation" do
      expect do
        described_class.new(chat: chat, scope: {adapter_name: :test, channel_id: "", thread_id: "T1"})
      end.to raise_error(ChatSDK::ConfigurationError, /channel_id must not be empty/)
    end

    it "rejects an empty thread scope ID but accepts a channel scope" do
      expect do
        described_class.new(chat: chat, scope: {adapter_name: :test, channel_id: "C1", thread_id: ""})
      end.to raise_error(ChatSDK::ConfigurationError, /thread_id must not be empty/)

      expect do
        described_class.new(chat: chat, scope: {adapter_name: :test, channel_id: "C1", thread_id: nil})
      end.not_to raise_error
    end

    it "requires scope for tools run inside a handler without a conversation" do
      expect do
        ChatSDK::AI::ConversationScope.with(nil) do
          executor.execute(:fetch_messages, {adapter_name: "test", channel_id: "C1"})
        end
      end.to raise_error(ChatSDK::Error, /requires an explicit scope/)
    end

    it "allows workspace-wide access with scope false inside a handler" do
      unscoped = described_class.new(chat: chat, scope: false)

      expect do
        ChatSDK::AI::ConversationScope.with(nil) do
          unscoped.execute(:fetch_messages, {adapter_name: "test", channel_id: "C1"})
        end
      end.not_to raise_error
    end

    it "executes fetch_messages" do
      result = executor.execute(:fetch_messages, {adapter_name: "test", channel_id: "C1"})
      expect(result).to eq([])
    end

    it "executes fetch_thread" do
      result = executor.execute(:fetch_thread, {adapter_name: "test", channel_id: "C1", thread_id: "T1"})
      expect(result).to eq([])
    end

    it "blocks access outside an explicit conversation scope" do
      scoped = described_class.new(chat: chat, scope: {adapter_name: :test, channel_id: "C1", thread_id: "T1"})

      expect do
        scoped.execute(:fetch_messages, {adapter_name: "test", channel_id: "C2"})
      end.to raise_error(ChatSDK::Error, /tool call blocked/)
    end

    it "allows sibling threads in the scoped channel by default" do
      scoped = described_class.new(chat: chat, scope: {adapter_name: :test, channel_id: "C1", thread_id: "T1"})

      expect do
        scoped.execute(:fetch_thread, {adapter_name: "test", channel_id: "C1", thread_id: "T2"})
      end.not_to raise_error
    end

    it "blocks sibling threads in strict scope mode" do
      scoped = described_class.new(
        chat: chat,
        scope: {adapter_name: :test, channel_id: "C1", thread_id: "T1"},
        strict_scope: true
      )

      expect do
        scoped.execute(:fetch_thread, {adapter_name: "test", channel_id: "C1", thread_id: "T2"})
      end.to raise_error(ChatSDK::Error, /tool call blocked/)
    end

    it "inherits the currently handled conversation" do
      thread = chat.channel("C1", adapter_name: :test).thread("T1")

      ChatSDK::AI::ConversationScope.with(thread) do
        expect do
          executor.execute(:fetch_messages, {adapter_name: "test", channel_id: "C2"})
        end.to raise_error(ChatSDK::Error, /tool call blocked/)
      end
    end
  end
end
