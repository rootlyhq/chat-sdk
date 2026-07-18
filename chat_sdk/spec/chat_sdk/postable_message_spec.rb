require_relative "../../../spec/spec_helper"

RSpec.describe ChatSDK::PostableMessage do
  describe ".from" do
    it "wraps a string" do
      msg = described_class.from("hello")
      expect(msg.text).to eq("hello")
      expect(msg.card?).to be false
    end

    it "passes through a PostableMessage" do
      original = described_class.new(text: "hello")
      expect(described_class.from(original)).to equal(original)
    end

    it "wraps a card node" do
      card = ChatSDK.card(title: "Test") { text "body" }
      msg = described_class.from(card)
      expect(msg.card?).to be true
      expect(msg.card).to eq(card)
    end

    it "raises for unknown types" do
      expect { described_class.from(123) }.to raise_error(ArgumentError)
    end
  end

  it "requires text or card" do
    expect { described_class.new }.to raise_error(ArgumentError)
  end
end
