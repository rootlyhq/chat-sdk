# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

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
end
