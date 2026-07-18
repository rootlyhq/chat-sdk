# frozen_string_literal: true

require_relative "../../../../spec/spec_helper"

RSpec.describe ChatSDK::AI::ToolBuilder do
  describe "#build" do
    it "builds reader preset with only read tools" do
      tools = described_class.new(preset: :reader).build
      expect(tools.keys).to eq(%i[fetch_messages fetch_thread])
    end

    it "builds messenger preset with read, post, DM, react, and typing tools" do
      tools = described_class.new(preset: :messenger).build
      expect(tools.keys).to eq(%i[fetch_messages fetch_thread post_message send_direct_message add_reaction start_typing])
    end

    it "builds moderator preset with edit and delete tools" do
      tools = described_class.new(preset: :moderator).build
      expect(tools.keys).to include(:edit_message, :delete_message, :remove_reaction)
    end

    it "marks read-only tools as not requiring approval" do
      tools = described_class.new(preset: :messenger, require_approval: true).build
      expect(tools[:fetch_messages][:requires_approval]).to be false
      expect(tools[:fetch_thread][:requires_approval]).to be false
    end

    it "marks write tools as requiring approval when enabled" do
      tools = described_class.new(preset: :messenger, require_approval: true).build
      expect(tools[:post_message][:requires_approval]).to be true
      expect(tools[:send_direct_message][:requires_approval]).to be true
      expect(tools[:add_reaction][:requires_approval]).to be true
    end

    it "disables approval for write tools when require_approval is false" do
      tools = described_class.new(preset: :messenger, require_approval: false).build
      expect(tools[:post_message][:requires_approval]).to be false
    end

    it "raises on unknown preset" do
      expect { described_class.new(preset: :unknown) }
        .to raise_error(ChatSDK::ConfigurationError, /Unknown preset/)
    end

    it "accepts string preset and converts to symbol" do
      tools = described_class.new(preset: "reader").build
      expect(tools.keys).to eq(%i[fetch_messages fetch_thread])
    end

    it "includes description and parameters for each tool" do
      tools = described_class.new(preset: :reader).build
      tools.each_value do |defn|
        expect(defn).to have_key(:description)
        expect(defn).to have_key(:parameters)
        expect(defn[:parameters]).to have_key(:properties)
        expect(defn[:parameters]).to have_key(:required)
      end
    end
  end
end
