# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

RSpec.describe ChatSDK::Message do
  let(:author) { ChatSDK::Author.new(id: "U1", name: "Alice", platform: :slack) }

  describe "attributes" do
    it "stores all fields" do
      msg = described_class.new(
        id: "M1",
        text: "hello",
        author: author,
        thread_id: "T1",
        channel_id: "C1",
        platform: :slack,
        attachments: ["file.png"],
        timestamp: 1_700_000_000
      )
      expect(msg.id).to eq("M1")
      expect(msg.text).to eq("hello")
      expect(msg.author).to eq(author)
      expect(msg.thread_id).to eq("T1")
      expect(msg.channel_id).to eq("C1")
      expect(msg.platform).to eq(:slack)
      expect(msg.attachments).to eq(["file.png"])
      expect(msg.timestamp).to eq(1_700_000_000)
    end

    it "defaults attachments to empty array" do
      msg = described_class.new(
        id: "M1",
        text: "hello",
        author: author,
        thread_id: "T1",
        channel_id: "C1",
        platform: :slack
      )
      expect(msg.attachments).to eq([])
    end

    it "defaults timestamp to nil" do
      msg = described_class.new(
        id: "M1",
        text: "hello",
        author: author,
        thread_id: "T1",
        channel_id: "C1",
        platform: :slack
      )
      expect(msg.timestamp).to be_nil
    end
  end

  describe "equality" do
    it "equals another message with the same id and platform" do
      a = described_class.new(id: "M1", text: "hello", author: author, thread_id: "T1", channel_id: "C1", platform: :slack)
      b = described_class.new(id: "M1", text: "different", author: author, thread_id: "T2", channel_id: "C2", platform: :slack)
      expect(a).to eq(b)
    end

    it "does not equal a message with a different id" do
      a = described_class.new(id: "M1", text: "hello", author: author, thread_id: "T1", channel_id: "C1", platform: :slack)
      b = described_class.new(id: "M2", text: "hello", author: author, thread_id: "T1", channel_id: "C1", platform: :slack)
      expect(a).not_to eq(b)
    end

    it "does not equal a message on a different platform" do
      a = described_class.new(id: "M1", text: "hello", author: author, thread_id: "T1", channel_id: "C1", platform: :slack)
      b = described_class.new(id: "M1", text: "hello", author: author, thread_id: "T1", channel_id: "C1", platform: :teams)
      expect(a).not_to eq(b)
    end

    it "does not equal a non-Message object" do
      msg = described_class.new(id: "M1", text: "hello", author: author, thread_id: "T1", channel_id: "C1", platform: :slack)
      expect(msg).not_to eq("M1")
    end
  end

  describe "hash equality" do
    it "produces the same hash for equal messages" do
      a = described_class.new(id: "M1", text: "hello", author: author, thread_id: "T1", channel_id: "C1", platform: :slack)
      b = described_class.new(id: "M1", text: "different", author: author, thread_id: "T2", channel_id: "C2", platform: :slack)
      expect(a.hash).to eq(b.hash)
    end

    it "can be used as hash keys" do
      a = described_class.new(id: "M1", text: "hello", author: author, thread_id: "T1", channel_id: "C1", platform: :slack)
      b = described_class.new(id: "M1", text: "different", author: author, thread_id: "T2", channel_id: "C2", platform: :slack)
      h = {a => "value"}
      expect(h[b]).to eq("value")
    end
  end
end
