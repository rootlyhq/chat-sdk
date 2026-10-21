# frozen_string_literal: true

require_relative "../../../spec/spec_helper"
require "json"

RSpec.describe ChatSDK::EventSerializer do
  let(:author) { ChatSDK::Author.new(id: "U1", name: "Alice", platform: :test) }

  it "round-trips the message mention flag" do
    message = ChatSDK::Message.new(
      id: "M1", text: "@bot", author: author, thread_id: "T1", channel_id: "C1",
      platform: :test, is_mention: false
    )
    event = ChatSDK::Events::Mention.new(
      message: message, thread_id: "T1", channel_id: "C1",
      platform: :test, adapter_name: :test, raw: {"team_id" => "W1"}
    )

    loaded = described_class.load(described_class.dump(event))

    expect(loaded.message.is_mention).to be(false)
    expect(loaded.raw).to eq("team_id" => "W1")
  end

  it "round-trips action values" do
    event = ChatSDK::Events::Action.new(
      action_id: "submit", values: {"form" => {"name" => "Alice"}},
      thread_id: "T1", channel_id: "C1", platform: :test, adapter_name: :test
    )

    loaded = described_class.load(described_class.dump(event))

    expect(loaded.values).to eq("form" => {"name" => "Alice"})
  end

  it "round-trips installation events" do
    event = ChatSDK::Events::Installed.new(
      installation_id: "team-1",
      team_id: "team-1",
      tenant_id: "tenant-1",
      conversation_id: "conversation-1",
      action: "add-upgrade",
      user: ChatSDK::Author.new(id: "installer-1", name: "Installer", platform: :teams),
      platform: :teams,
      adapter_name: :teams,
      raw: {"type" => "installationUpdate"}
    )

    loaded = described_class.load(described_class.dump(event))

    expect(loaded).to be_a(ChatSDK::Events::Installed)
    expect(loaded.installation_id).to eq("team-1")
    expect(loaded.team_id).to eq("team-1")
    expect(loaded.tenant_id).to eq("tenant-1")
    expect(loaded.conversation_id).to eq("conversation-1")
    expect(loaded.action).to eq("add-upgrade")
    expect(loaded.user.id).to eq("installer-1")
    expect(loaded.raw).to eq("type" => "installationUpdate")
  end

  it "round-trips assistant thread started events and stringifies context keys" do
    event = ChatSDK::Events::AssistantThreadStarted.new(
      thread_id: "1234.5678",
      channel_id: "D123",
      thread_ts: "1234.5678",
      user_id: "U123",
      context: ChatSDK::Events::AssistantContext.new(channel_id: "C456", team_id: "T789", force_search: true),
      platform: :slack,
      adapter_name: :slack,
      raw: {"event_id" => "Ev1"},
      timestamp: Time.iso8601("2026-10-21T18:01:00.123456Z")
    )

    dumped = JSON.parse(JSON.generate(described_class.dump(event)))
    loaded = described_class.load(dumped)

    expect(dumped["context"]).to eq("channel_id" => "C456", "team_id" => "T789", "enterprise_id" => nil, "thread_entry_point" => nil, "force_search" => true)
    expect(loaded).to be_a(ChatSDK::Events::AssistantThreadStarted)
    expect(loaded.thread_id).to eq("1234.5678")
    expect(loaded.thread_ts).to eq("1234.5678")
    expect(loaded.channel_id).to eq("D123")
    expect(loaded.user_id).to eq("U123")
    expect(loaded.context).to eq(event.context)
    expect(loaded.platform).to eq(:slack)
    expect(loaded.adapter_name).to eq(:slack)
    expect(loaded.raw).to eq("event_id" => "Ev1")
    expect(loaded.timestamp).to eq(event.timestamp)
  end

  it "round-trips assistant context changed events" do
    event = ChatSDK::Events::AssistantContextChanged.new(
      thread_id: "1234.5678",
      channel_id: "D123",
      thread_ts: "1234.5678",
      user_id: "U123",
      context: {
        "channel_id" => "C456",
        "team_id" => "T789",
        "enterprise_id" => "E1",
        "thread_entry_point" => "sidebar",
        "force_search" => true
      },
      platform: :slack,
      adapter_name: :slack,
      raw: {"event_id" => "Ev2"},
      timestamp: Time.iso8601("2026-10-21T18:01:00.234567Z")
    )

    loaded = described_class.load(JSON.parse(JSON.generate(described_class.dump(event))))

    expect(loaded).to be_a(ChatSDK::Events::AssistantContextChanged)
    expect(loaded.thread_id).to eq("1234.5678")
    expect(loaded.channel_id).to eq("D123")
    expect(loaded.thread_ts).to eq("1234.5678")
    expect(loaded.user_id).to eq("U123")
    expect(loaded.context).to eq(event.context)
    expect(loaded.platform).to eq(:slack)
    expect(loaded.adapter_name).to eq(:slack)
    expect(loaded.raw).to eq("event_id" => "Ev2")
    expect(loaded.timestamp).to eq(event.timestamp)
  end

  it "round-trips App Home opened events" do
    event = ChatSDK::Events::AppHomeOpened.new(
      user_id: "U123",
      channel_id: "D123",
      tab: "home",
      platform: :slack,
      adapter_name: :slack,
      raw: {"event_id" => "Ev3"},
      timestamp: Time.iso8601("2026-10-21T18:01:00.345678Z")
    )

    loaded = described_class.load(JSON.parse(JSON.generate(described_class.dump(event))))

    expect(loaded).to be_a(ChatSDK::Events::AppHomeOpened)
    expect(loaded.user_id).to eq("U123")
    expect(loaded.channel_id).to eq("D123")
    expect(loaded.tab).to eq("home")
    expect(loaded.platform).to eq(:slack)
    expect(loaded.adapter_name).to eq(:slack)
    expect(loaded.raw).to eq("event_id" => "Ev3")
    expect(loaded.timestamp).to eq(event.timestamp)
  end

  it "round-trips member joined channel events" do
    event = ChatSDK::Events::MemberJoinedChannel.new(
      user_id: "U123",
      channel_id: "C456",
      inviter_id: "U789",
      platform: :slack,
      adapter_name: :slack,
      raw: {"event_id" => "Ev4"},
      timestamp: Time.iso8601("2026-10-21T18:01:00.456789Z")
    )

    loaded = described_class.load(JSON.parse(JSON.generate(described_class.dump(event))))

    expect(loaded).to be_a(ChatSDK::Events::MemberJoinedChannel)
    expect(loaded.user_id).to eq("U123")
    expect(loaded.channel_id).to eq("C456")
    expect(loaded.inviter_id).to eq("U789")
    expect(loaded.platform).to eq(:slack)
    expect(loaded.adapter_name).to eq(:slack)
    expect(loaded.raw).to eq("event_id" => "Ev4")
    expect(loaded.timestamp).to eq(event.timestamp)
  end

  it "preserves sub-second event, message, and deletion timestamps through JSON" do
    event_timestamp = Time.iso8601("2026-10-21T18:01:00.123456Z")
    message_timestamp = Time.iso8601("2026-10-21T18:01:00.358023Z")
    deleted_at = Time.iso8601("2026-10-21T18:01:00.469134Z")
    message = ChatSDK::Message.new(
      id: "M1",
      text: "hello",
      author: author,
      thread_id: "T1",
      channel_id: "C1",
      platform: :test,
      timestamp: message_timestamp
    )
    event = ChatSDK::Events::Mention.new(
      message: message,
      thread_id: "T1",
      channel_id: "C1",
      platform: :test,
      adapter_name: :test,
      timestamp: event_timestamp
    )
    serialized_event = JSON.parse(JSON.generate(described_class.dump(event)))
    loaded_event = described_class.load(serialized_event)

    deleted_event = ChatSDK::Events::MessageDeleted.new(
      message_id: "M1",
      previous_message: message,
      deleted_at: deleted_at,
      thread_id: "T1",
      channel_id: "C1",
      platform: :test,
      adapter_name: :test,
      timestamp: event_timestamp
    )
    serialized_deleted_event = JSON.parse(JSON.generate(described_class.dump(deleted_event)))
    loaded_deleted_event = described_class.load(serialized_deleted_event)

    expect(loaded_event.timestamp.to_f).to eq(event_timestamp.to_f)
    expect(loaded_event.message.timestamp.to_f).to eq(message_timestamp.to_f)
    expect(loaded_deleted_event.deleted_at.to_f).to eq(deleted_at.to_f)
  end

  it "loads legacy whole-second timestamps" do
    timestamp = "2026-10-21T18:01:00Z"
    event = described_class.load(
      "type" => "reaction",
      "platform" => "test",
      "adapter_name" => "test",
      "thread_id" => "T1",
      "channel_id" => "C1",
      "timestamp" => timestamp,
      "emoji" => "fire",
      "user_id" => "U1",
      "message_id" => "M1",
      "added" => true
    )

    expect(event.timestamp).to eq(Time.iso8601(timestamp))
  end
end
