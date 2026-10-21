# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::Slack::EventParser do
  def parse_message(event)
    described_class.parse({"type" => "event_callback", "event" => event}).first.message
  end

  it "builds text from supported Slack blocks in their original order" do
    message = parse_message({
      "type" => "message",
      "user" => "U1",
      "text" => "fallback",
      "ts" => "1.0",
      "channel" => "C1",
      "blocks" => [
        {"type" => "section", "text" => {"type" => "mrkdwn", "text" => "section"}},
        {"type" => "header", "text" => {"type" => "plain_text", "text" => "header"}},
        {"type" => "context", "elements" => [{"type" => "mrkdwn", "text" => "context"}]},
        {"type" => "image", "alt_text" => "chart"},
        {"type" => "divider"},
        {"type" => "actions", "elements" => [{"type" => "button", "text" => {"text" => "Approve"}}]},
        {"type" => "table", "rows" => [[{"text" => "A"}, {"text" => "B"}]]}
      ]
    })

    expect(message.text).to eq("section\nheader\ncontext\nchart\nApprove\nA | B")
  end

  it "preserves the text field when an unsupported block is present" do
    message = parse_message({
      "type" => "message",
      "user" => "U1",
      "text" => "fallback text",
      "ts" => "1.0",
      "channel" => "C1",
      "blocks" => [
        {"type" => "section", "text" => {"type" => "mrkdwn", "text" => "block text"}},
        {"type" => "rich_text", "elements" => []}
      ]
    })

    expect(message.text).to eq("fallback text")
  end
end
