# frozen_string_literal: true

require_relative "../../../../spec/spec_helper"

RSpec.describe ChatSDK::Streaming::Chunk do
  describe ".normalize" do
    it "keeps markdown text as strings" do
      expect(described_class.normalize("hello")).to eq("hello")
    end

    it "normalizes markdown text hashes" do
      chunk = described_class.normalize(type: "markdown_text", text: "hello")

      expect(chunk).to be_a(ChatSDK::Streaming::MarkdownTextChunk)
      expect(chunk.text).to eq("hello")
      expect(chunk.to_h).to eq(type: "markdown_text", text: "hello")
    end

    it "normalizes task and plan update hashes" do
      task = described_class.normalize(
        "type" => "task_update",
        "id" => "task-1",
        "title" => "Check",
        "status" => "in_progress"
      )
      plan = described_class.normalize(type: "plan_update", title: "Plan")

      expect(task).to eq(ChatSDK::Streaming::TaskUpdateChunk.new(
        id: "task-1",
        title: "Check",
        status: "in_progress"
      ))
      expect(plan).to eq(ChatSDK::Streaming::PlanUpdateChunk.new(title: "Plan"))
      expect(task.to_h).to eq(
        type: "task_update",
        id: "task-1",
        title: "Check",
        status: "in_progress"
      )
      expect(plan.to_h).to eq(type: "plan_update", title: "Plan")
    end

    it "returns nil for hashes without a recognized type" do
      expect(described_class.normalize({})).to be_nil
      expect(described_class.normalize(type: "unknown")).to be_nil
    end

    it "rejects unsupported task statuses" do
      expect {
        ChatSDK::Streaming::TaskUpdateChunk.new(id: "task-1", title: "Check", status: "running")
      }.to raise_error(ArgumentError, /status must be one of/)
    end

    it "accepts every supported task status" do
      statuses = %w[pending in_progress complete error]

      expect(statuses.map do |status|
        ChatSDK::Streaming::TaskUpdateChunk.new(id: "task-1", title: "Check", status: status).status
      end).to eq(statuses)
    end
  end

  describe ".text_of" do
    it "extracts text from strings and markdown chunks only" do
      expect(described_class.text_of("hello")).to eq("hello")
      expect(described_class.text_of(ChatSDK::Streaming::MarkdownTextChunk.new(text: "world"))).to eq("world")
      expect(described_class.text_of(ChatSDK::Streaming::TaskUpdateChunk.new(
        id: "task-1",
        title: "Check",
        status: "pending"
      ))).to be_nil
    end
  end
end
