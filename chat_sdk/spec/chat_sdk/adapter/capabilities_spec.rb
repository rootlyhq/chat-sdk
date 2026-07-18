# frozen_string_literal: true

require_relative "../../../../spec/spec_helper"

RSpec.describe ChatSDK::Adapter::Capabilities do
  let(:adapter_class) do
    Class.new do
      include ChatSDK::Adapter::Capabilities
    end
  end

  describe "declaring capabilities" do
    it "declares capabilities on the class" do
      adapter_class.capabilities(:edit_messages, :threads)
      expect(adapter_class.declared_capabilities).to eq(%i[edit_messages threads])
    end

    it "returns empty array when no capabilities declared" do
      expect(adapter_class.declared_capabilities).to eq([])
    end
  end

  describe "#supports?" do
    it "returns true for declared capabilities" do
      adapter_class.capabilities(:edit_messages, :reactions)
      instance = adapter_class.new
      expect(instance.supports?(:edit_messages)).to be true
      expect(instance.supports?(:reactions)).to be true
    end

    it "returns false for undeclared capabilities" do
      adapter_class.capabilities(:edit_messages)
      instance = adapter_class.new
      expect(instance.supports?(:reactions)).to be false
    end
  end

  describe "unknown capabilities" do
    it "raises ArgumentError for unknown capabilities" do
      expect {
        adapter_class.capabilities(:edit_messages, :teleportation)
      }.to raise_error(ArgumentError, /Unknown capabilities: teleportation/)
    end
  end

  describe "KNOWN constant" do
    it "contains expected capabilities" do
      expected = %i[
        edit_messages delete_messages ephemeral_messages
        file_uploads reactions modals typing_indicator
        streaming_edit threads direct_messages
        scheduled_messages message_history
      ]
      expect(ChatSDK::Adapter::Capabilities::KNOWN).to match_array(expected)
    end

    it "is frozen" do
      expect(ChatSDK::Adapter::Capabilities::KNOWN).to be_frozen
    end
  end
end
