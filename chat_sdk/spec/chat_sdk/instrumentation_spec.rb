# frozen_string_literal: true

require "chat_sdk"

RSpec.describe ChatSDK::Instrumentation do
  after { described_class.reset! }

  describe ".subscribe / .instrument" do
    it "notifies subscribers with event name and payload" do
      events = []
      described_class.subscribe("test.chat_sdk") { |name, payload| events << [name, payload] }

      described_class.instrument("test.chat_sdk", foo: "bar")

      expect(events.length).to eq(1)
      expect(events.first[0]).to eq("test.chat_sdk")
      expect(events.first[1][:foo]).to eq("bar")
      expect(events.first[1][:duration]).to be_a(Float)
    end

    it "measures block duration" do
      duration = nil
      described_class.subscribe("test.chat_sdk") { |_, payload| duration = payload[:duration] }

      described_class.instrument("test.chat_sdk") { sleep(0.01) }

      expect(duration).to be >= 0.01
    end

    it "returns block result" do
      result = described_class.instrument("test.chat_sdk") { 42 }
      expect(result).to eq(42)
    end

    it "reports errors and re-raises" do
      error = nil
      described_class.subscribe("test.chat_sdk") { |_, payload| error = payload[:error] }

      expect {
        described_class.instrument("test.chat_sdk") { raise "boom" }
      }.to raise_error(RuntimeError, "boom")

      expect(error).to be_a(RuntimeError)
      expect(error.message).to eq("boom")
    end
  end

  describe ".unsubscribe" do
    it "removes a subscriber" do
      count = 0
      block = described_class.subscribe("test.chat_sdk") { count += 1 }

      described_class.instrument("test.chat_sdk")
      expect(count).to eq(1)

      described_class.unsubscribe("test.chat_sdk", block)
      described_class.instrument("test.chat_sdk")
      expect(count).to eq(1)
    end
  end

  describe ".reset!" do
    it "clears all subscribers" do
      count = 0
      described_class.subscribe("test.chat_sdk") { count += 1 }

      described_class.reset!
      described_class.instrument("test.chat_sdk")
      expect(count).to eq(0)
    end
  end
end
