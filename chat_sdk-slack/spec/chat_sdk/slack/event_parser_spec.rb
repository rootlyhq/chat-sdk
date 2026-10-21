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

  it "parses assistant_thread_started with Slack context" do
    event = {
      "type" => "assistant_thread_started",
      "event_ts" => "1234567890.123456",
      "assistant_thread" => {
        "user_id" => "U123",
        "channel_id" => "D456",
        "thread_ts" => "1234567890.654321",
        "context" => {"channel_id" => "C789", "team_id" => "T012"}
      }
    }

    parsed = described_class.parse({"type" => "event_callback", "event" => event}).first

    expect(parsed).to be_a(ChatSDK::Events::AssistantThreadStarted)
    expect(parsed.thread_id).to eq("1234567890.654321")
    expect(parsed.channel_id).to eq("D456")
    expect(parsed.thread_ts).to eq("1234567890.654321")
    expect(parsed.user_id).to eq("U123")
    expect(parsed.context).to eq(ChatSDK::Events::AssistantContext.new(channel_id: "C789", team_id: "T012"))
    expect(parsed.timestamp).to eq(Time.at(1_234_567_890.123456))
    expect(parsed.platform).to eq(:slack)
    expect(parsed.adapter_name).to eq(:slack)
  end

  it "parses assistant_thread_context_changed" do
    event = {
      "type" => "assistant_thread_context_changed",
      "event_ts" => "1234567890.123456",
      "assistant_thread" => {
        "user_id" => "U123",
        "channel_id" => "D456",
        "thread_ts" => "1234567890.654321",
        "context" => {"team_id" => "T012", "force_search" => true}
      }
    }

    parsed = described_class.parse({"type" => "event_callback", "event" => event}).first

    expect(parsed).to be_a(ChatSDK::Events::AssistantContextChanged)
    expect(parsed.context).to eq(ChatSDK::Events::AssistantContext.new(team_id: "T012", force_search: true))
  end

  it "ignores assistant thread events without assistant_thread data" do
    event = {"type" => "assistant_thread_started"}

    expect(described_class.parse({"type" => "event_callback", "event" => event})).to eq([])
  end

  it "parses app_home_opened for the Home tab and ignores other tabs" do
    home = {
      "type" => "app_home_opened",
      "user" => "U123",
      "channel" => "D456",
      "tab" => "home",
      "event_ts" => "1234567890.123456"
    }

    parsed = described_class.parse({"type" => "event_callback", "event" => home}).first

    expect(parsed).to be_a(ChatSDK::Events::AppHomeOpened)
    expect(parsed.user_id).to eq("U123")
    expect(parsed.channel_id).to eq("D456")
    expect(parsed.tab).to eq("home")
    expect(parsed.timestamp).to eq(Time.at(1_234_567_890.123456))
    expect(described_class.parse({"type" => "event_callback", "event" => home.merge("tab" => "messages")})).to eq([])
  end

  it "parses member_joined_channel with an inviter" do
    event = {
      "type" => "member_joined_channel",
      "user" => "U123",
      "channel" => "C456",
      "inviter" => "U789",
      "event_ts" => "1234567890.123456"
    }

    parsed = described_class.parse({"type" => "event_callback", "event" => event}).first

    expect(parsed).to be_a(ChatSDK::Events::MemberJoinedChannel)
    expect(parsed.user_id).to eq("U123")
    expect(parsed.channel_id).to eq("C456")
    expect(parsed.inviter_id).to eq("U789")
    expect(parsed.timestamp).to eq(Time.at(1_234_567_890.123456))
  end
end
