# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

RSpec.describe ChatSDK::Config do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }

  describe "valid initialization" do
    it "creates with all required params" do
      config = described_class.new(user_name: "bot", adapters: {test: adapter}, state: state)
      expect(config.user_name).to eq("bot")
      expect(config.adapters).to eq({test: adapter})
      expect(config.state).to eq(state)
    end
  end

  describe "validation errors" do
    it "raises ConfigurationError for nil user_name" do
      expect {
        described_class.new(user_name: nil, adapters: {test: adapter}, state: state)
      }.to raise_error(ChatSDK::ConfigurationError, "user_name is required")
    end

    it "raises ConfigurationError for empty user_name" do
      expect {
        described_class.new(user_name: "", adapters: {test: adapter}, state: state)
      }.to raise_error(ChatSDK::ConfigurationError, "user_name is required")
    end

    it "raises ConfigurationError for empty adapters" do
      expect {
        described_class.new(user_name: "bot", adapters: {}, state: state)
      }.to raise_error(ChatSDK::ConfigurationError, "adapters hash is required")
    end

    it "raises ConfigurationError for nil adapters" do
      expect {
        described_class.new(user_name: "bot", adapters: nil, state: state)
      }.to raise_error(ChatSDK::ConfigurationError, "adapters hash is required")
    end

    it "raises ConfigurationError for missing state" do
      expect {
        described_class.new(user_name: "bot", adapters: {test: adapter}, state: nil)
      }.to raise_error(ChatSDK::ConfigurationError, "state adapter is required")
    end
  end

  describe "default values" do
    subject { described_class.new(user_name: "bot", adapters: {test: adapter}, state: state) }

    it "applies default dedupe_ttl" do
      expect(subject.dedupe_ttl).to eq(600)
    end

    it "applies default streaming_update_interval" do
      expect(subject.streaming_update_interval).to eq(0.5)
    end

    it "applies default on_lock_conflict" do
      expect(subject.on_lock_conflict).to eq(:drop)
    end

    it "applies default handler_executor" do
      expect(subject.handler_executor).to eq(:inline)
    end

    it "applies default log_level" do
      expect(subject.log_level).to eq(:info)
    end
  end

  describe "custom values" do
    it "overrides defaults with custom values" do
      config = described_class.new(
        user_name: "bot",
        adapters: {test: adapter},
        state: state,
        dedupe_ttl: 300,
        streaming_update_interval: 1.0,
        handler_executor: :threaded,
        log_level: :debug
      )
      expect(config.dedupe_ttl).to eq(300)
      expect(config.streaming_update_interval).to eq(1.0)
      expect(config.handler_executor).to eq(:threaded)
      expect(config.log_level).to eq(:debug)
    end
  end

  describe "on_lock_conflict validation" do
    it "accepts :drop" do
      config = described_class.new(user_name: "bot", adapters: {test: adapter}, state: state, on_lock_conflict: :drop)
      expect(config.on_lock_conflict).to eq(:drop)
    end

    it "accepts :force" do
      config = described_class.new(user_name: "bot", adapters: {test: adapter}, state: state, on_lock_conflict: :force)
      expect(config.on_lock_conflict).to eq(:force)
    end

    it "accepts a callable" do
      handler = ->(_lock) { :force }
      config = described_class.new(user_name: "bot", adapters: {test: adapter}, state: state, on_lock_conflict: handler)
      expect(config.on_lock_conflict).to eq(handler)
    end

    it "raises ConfigurationError for invalid on_lock_conflict" do
      expect {
        described_class.new(user_name: "bot", adapters: {test: adapter}, state: state, on_lock_conflict: :invalid)
      }.to raise_error(ChatSDK::ConfigurationError, "on_lock_conflict must be :drop, :force, or a callable")
    end
  end
end
