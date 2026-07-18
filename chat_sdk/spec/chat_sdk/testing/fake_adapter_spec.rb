require_relative "../../../../spec/spec_helper"
require "chat_sdk/testing"

# Force autoload of shared examples
ChatSDK::Testing::AdapterContract

RSpec.describe ChatSDK::Testing::FakeAdapter do
  subject { described_class.new }

  it_behaves_like "a chat_sdk platform adapter"

  describe "#simulate_mention" do
    it "dispatches a mention event" do
      bot = ChatSDK::Testing.build_bot(adapters: { test: subject })
      received = nil
      bot.on_new_mention { |_thread, msg| received = msg.text }
      subject.simulate_mention(bot, text: "hello")
      expect(received).to eq("hello")
    end
  end

  describe "#simulate_action" do
    it "dispatches an action event" do
      bot = ChatSDK::Testing.build_bot(adapters: { test: subject })
      received_id = nil
      bot.on_action("btn:1") { |event| received_id = event.action_id }
      subject.simulate_action(bot, action_id: "btn:1")
      expect(received_id).to eq("btn:1")
    end
  end

  describe "#post_message" do
    it "records posted messages" do
      subject.post_message(channel_id: "C1", message: ChatSDK::PostableMessage.new(text: "hi"))
      expect(subject.posted_messages.size).to eq(1)
      expect(subject.posted_messages.first[:message].text).to eq("hi")
    end
  end

  describe "#reset!" do
    it "clears all recorded calls" do
      subject.post_message(channel_id: "C1", message: ChatSDK::PostableMessage.new(text: "hi"))
      subject.reset!
      expect(subject.posted_messages).to be_empty
    end
  end
end
