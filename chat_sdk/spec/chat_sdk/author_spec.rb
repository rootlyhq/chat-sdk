# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

RSpec.describe ChatSDK::Author do
  describe "attributes" do
    it "stores id, name, and platform" do
      author = described_class.new(id: "U1", name: "Alice", platform: :slack)
      expect(author.id).to eq("U1")
      expect(author.name).to eq("Alice")
      expect(author.platform).to eq(:slack)
    end
  end

  describe "#bot?" do
    it "returns true when bot flag is set" do
      author = described_class.new(id: "B1", name: "Bot", platform: :slack, bot: true)
      expect(author.bot?).to be true
    end

    it "returns false when bot flag is not set" do
      author = described_class.new(id: "U1", name: "Human", platform: :slack)
      expect(author.bot?).to be false
    end

    it "returns false when bot is explicitly false" do
      author = described_class.new(id: "U1", name: "Human", platform: :slack, bot: false)
      expect(author.bot?).to be false
    end
  end

  describe "equality" do
    it "equals another author with the same id and platform" do
      a = described_class.new(id: "U1", name: "Alice", platform: :slack)
      b = described_class.new(id: "U1", name: "Bob", platform: :slack)
      expect(a).to eq(b)
    end

    it "does not equal an author with a different id" do
      a = described_class.new(id: "U1", name: "Alice", platform: :slack)
      b = described_class.new(id: "U2", name: "Alice", platform: :slack)
      expect(a).not_to eq(b)
    end

    it "does not equal an author on a different platform" do
      a = described_class.new(id: "U1", name: "Alice", platform: :slack)
      b = described_class.new(id: "U1", name: "Alice", platform: :teams)
      expect(a).not_to eq(b)
    end

    it "does not equal a non-Author object" do
      author = described_class.new(id: "U1", name: "Alice", platform: :slack)
      expect(author).not_to eq("U1")
    end
  end

  describe "hash equality" do
    it "produces the same hash for equal authors" do
      a = described_class.new(id: "U1", name: "Alice", platform: :slack)
      b = described_class.new(id: "U1", name: "Bob", platform: :slack)
      expect(a.hash).to eq(b.hash)
    end

    it "can be used as hash keys" do
      a = described_class.new(id: "U1", name: "Alice", platform: :slack)
      b = described_class.new(id: "U1", name: "Bob", platform: :slack)
      h = {a => "value"}
      expect(h[b]).to eq("value")
    end
  end
end
