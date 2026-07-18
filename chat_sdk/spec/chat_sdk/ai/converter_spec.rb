# frozen_string_literal: true

require_relative "../../../../spec/spec_helper"

RSpec.describe ChatSDK::AI::Converter do
  def build_message(id:, text:, bot: false, name: "user1", timestamp: nil, attachments: [])
    author = ChatSDK::Author.new(id: "A#{id}", name: name, platform: :test, bot: bot)
    ChatSDK::Message.new(
      id: id,
      text: text,
      author: author,
      thread_id: "T1",
      channel_id: "C1",
      platform: :test,
      timestamp: timestamp,
      attachments: attachments
    )
  end

  describe ".to_ai_messages" do
    it "converts bot messages to assistant role" do
      messages = [build_message(id: "1", text: "hello from bot", bot: true)]
      result = described_class.to_ai_messages(messages)
      expect(result.first[:role]).to eq("assistant")
    end

    it "converts user messages to user role" do
      messages = [build_message(id: "1", text: "hello from user", bot: false)]
      result = described_class.to_ai_messages(messages)
      expect(result.first[:role]).to eq("user")
    end

    it "filters empty messages" do
      messages = [
        build_message(id: "1", text: "valid"),
        build_message(id: "2", text: ""),
        build_message(id: "3", text: "   "),
        build_message(id: "4", text: nil)
      ]
      result = described_class.to_ai_messages(messages)
      expect(result.size).to eq(1)
      expect(result.first[:content]).to eq("valid")
    end

    it "sorts by timestamp" do
      messages = [
        build_message(id: "2", text: "second", timestamp: Time.at(200)),
        build_message(id: "1", text: "first", timestamp: Time.at(100)),
        build_message(id: "3", text: "third", timestamp: Time.at(300))
      ]
      result = described_class.to_ai_messages(messages)
      expect(result.map { |m| m[:content] }).to eq(%w[first second third])
    end

    it "falls back to sorting by id when timestamp is nil" do
      messages = [
        build_message(id: "b", text: "second"),
        build_message(id: "a", text: "first")
      ]
      result = described_class.to_ai_messages(messages)
      expect(result.map { |m| m[:content] }).to eq(%w[first second])
    end

    it "includes names when requested" do
      messages = [build_message(id: "1", text: "hello", name: "Alice")]
      result = described_class.to_ai_messages(messages, include_names: true)
      expect(result.first[:content]).to eq("[Alice]: hello")
    end

    it "does not prefix assistant messages with names" do
      messages = [build_message(id: "1", text: "hello", bot: true, name: "Bot")]
      result = described_class.to_ai_messages(messages, include_names: true)
      expect(result.first[:content]).to eq("hello")
    end

    it "applies transform block" do
      messages = [build_message(id: "1", text: "hello")]
      result = described_class.to_ai_messages(messages) do |msg, _original|
        msg.merge(extra: "data")
      end
      expect(result.first[:extra]).to eq("data")
    end

    it "allows transform block to filter by returning nil" do
      messages = [
        build_message(id: "1", text: "keep"),
        build_message(id: "2", text: "drop")
      ]
      result = described_class.to_ai_messages(messages) do |msg, _original|
        (msg[:content] == "drop") ? nil : msg
      end
      expect(result.size).to eq(1)
      expect(result.first[:content]).to eq("keep")
    end

    it "converts image attachments to image parts" do
      messages = [
        build_message(
          id: "1",
          text: "check this",
          attachments: [{url: "https://example.com/img.png", mime_type: "image/png"}]
        )
      ]
      result = described_class.to_ai_messages(messages)
      content = result.first[:content]
      expect(content).to be_an(Array)
      expect(content.first).to eq({type: "text", text: "check this"})
      expect(content.last).to eq({type: "image", url: "https://example.com/img.png", media_type: "image/png"})
    end

    it "converts file attachments to file parts" do
      messages = [
        build_message(
          id: "1",
          text: "see doc",
          attachments: [{url: "https://example.com/doc.pdf", mime_type: "application/pdf", filename: "doc.pdf"}]
        )
      ]
      result = described_class.to_ai_messages(messages)
      content = result.first[:content]
      expect(content.last).to eq({
        type: "file",
        url: "https://example.com/doc.pdf",
        filename: "doc.pdf",
        media_type: "application/pdf"
      })
    end

    it "converts non-hash attachments to text parts" do
      messages = [
        build_message(id: "1", text: "with attachment", attachments: ["plain text attachment"])
      ]
      result = described_class.to_ai_messages(messages)
      content = result.first[:content]
      expect(content.last).to eq({type: "text", text: "plain text attachment"})
    end
  end
end
