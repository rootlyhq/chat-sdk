require_relative "../../../spec/spec_helper"

RSpec.describe ChatSDK::EventRegistry do
  let(:registry) { described_class.new }

  describe "#register + #handlers_for" do
    it "matches by type" do
      registry.register(:mention) { |_t, _m| }
      event = ChatSDK::Events::Mention.new(
        message: ChatSDK::Message.new(id: "1", text: "hi", author: nil, thread_id: "T1", channel_id: "C1", platform: :test),
        thread_id: "T1", channel_id: "C1", platform: :test, adapter_name: :test
      )
      expect(registry.handlers_for(event).size).to eq(1)
    end

    it "matches action by action_id" do
      registry.register(:action, matcher: "btn:1") { |_e| }
      event = ChatSDK::Events::Action.new(
        action_id: "btn:1", thread_id: "T1", channel_id: "C1", platform: :test, adapter_name: :test
      )
      expect(registry.handlers_for(event).size).to eq(1)
    end

    it "does not match wrong action_id" do
      registry.register(:action, matcher: "btn:2") { |_e| }
      event = ChatSDK::Events::Action.new(
        action_id: "btn:1", thread_id: "T1", channel_id: "C1", platform: :test, adapter_name: :test
      )
      expect(registry.handlers_for(event)).to be_empty
    end

    it "matches reaction by emoji list" do
      registry.register(:reaction, matcher: %w[fire]) { |_e| }
      event = ChatSDK::Events::Reaction.new(
        emoji: "fire", user_id: "U1", message_id: "M1", thread_id: "T1", channel_id: "C1", platform: :test, adapter_name: :test
      )
      expect(registry.handlers_for(event).size).to eq(1)
    end

    it "matches mention by regex" do
      registry.register(:mention, matcher: /^help$/i) { |_t, _m| }
      msg = ChatSDK::Message.new(id: "1", text: "help", author: nil, thread_id: "T1", channel_id: "C1", platform: :test)
      event = ChatSDK::Events::Mention.new(
        message: msg, thread_id: "T1", channel_id: "C1", platform: :test, adapter_name: :test
      )
      expect(registry.handlers_for(event).size).to eq(1)
    end

    it "matches slash command by string" do
      registry.register(:slash_command, matcher: "/deploy") { |_e| }
      event = ChatSDK::Events::SlashCommand.new(
        command: "/deploy", user_id: "U1", channel_id: "C1", platform: :test, adapter_name: :test
      )
      expect(registry.handlers_for(event).size).to eq(1)
    end
  end
end
