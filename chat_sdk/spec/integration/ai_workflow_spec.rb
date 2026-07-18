# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

RSpec.describe "Integration: AI workflow" do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }
  let(:bot) { ChatSDK::Chat.new(user_name: "ai-bot", adapters: {test: adapter}, state: state) }

  describe "mention → fetch history → convert → respond" do
    it "simulates a full AI agent loop" do
      bot.on_new_mention do |thread, msg|
        thread.subscribe
        thread.post("Let me check...")

        messages, = thread.messages
        ai_messages = ChatSDK::AI.to_ai_messages(messages)

        thread.post("Processed #{ai_messages.size} messages")
      end

      adapter.simulate_mention(bot, text: "what happened?", channel_id: "C1")

      expect(adapter.posted_messages.size).to eq(2)
      expect(adapter.posted_messages.first[:message].text).to eq("Let me check...")
    end
  end

  describe "AI streaming with enumerable" do
    it "streams chunks from an array (simulating LLM output)" do
      thread = ChatSDK::Thread.new(id: "T1", channel_id: "C1", adapter: adapter, chat: bot)

      chunks = ["The ", "error ", "is ", "in ", "line ", "42."]
      thread.post_ai_stream(chunks, placeholder: "Analyzing...")

      expect(adapter.posted_messages.size).to be >= 1
      expect(adapter.posted_messages.first[:message].text).to eq("Analyzing...")
      expect(adapter.edited_messages.size).to be >= 1
    end

    it "streams from an Enumerator" do
      thread = ChatSDK::Thread.new(id: "T1", channel_id: "C1", adapter: adapter, chat: bot)

      enum = Enumerator.new do |y|
        y << "Processing"
        y << "..."
        y << " done!"
      end

      thread.post_ai_stream(enum)
      expect(adapter.edited_messages).not_to be_empty
    end
  end

  describe "tool executor round-trip" do
    it "posts via executor, then fetches via executor" do
      executor = ChatSDK::AI.create_executor(chat: bot)

      post_result = executor.execute(:post_message, {
        adapter_name: "test", channel_id: "C1", text: "AI posted this"
      })
      expect(post_result[:id]).to be_a(String)

      fetch_result = executor.execute(:fetch_messages, {
        adapter_name: "test", channel_id: "C1"
      })
      expect(fetch_result).to be_an(Array)
    end

    it "sends DM and reacts in sequence" do
      executor = ChatSDK::AI.create_executor(chat: bot)

      dm = executor.execute(:send_direct_message, {
        adapter_name: "test", user_id: "U1", text: "Hey!"
      })
      expect(dm[:channel_id]).to eq("dm_U1")

      executor.execute(:add_reaction, {
        adapter_name: "test", channel_id: "C1", message_id: "M1", emoji: "thumbsup"
      })
      expect(adapter.reactions_added.size).to eq(1)
    end
  end

  describe "tool definitions match presets" do
    it "reader has no write tools" do
      tools = ChatSDK::AI.create_tools(preset: :reader)
      tools.each_value do |defn|
        expect(defn[:requires_approval]).to be false
      end
    end

    it "moderator has all tools including destructive ones" do
      tools = ChatSDK::AI.create_tools(preset: :moderator)
      expect(tools).to have_key(:delete_message)
      expect(tools).to have_key(:edit_message)
      expect(tools).to have_key(:remove_reaction)
    end
  end
end
