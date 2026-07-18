# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

RSpec.describe "Integration: multi-adapter bot" do
  let(:slack) { ChatSDK::Testing::FakeAdapter.new }
  let(:teams) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }
  let(:bot) do
    ChatSDK::Chat.new(
      user_name: "multi-bot",
      adapters: {slack: slack, teams: teams},
      state: state
    )
  end

  def build_mention(text:, adapter_name:, channel_id: "C1", thread_id: "T1")
    author = ChatSDK::Author.new(id: "U1", name: "user", platform: adapter_name)
    message = ChatSDK::Message.new(id: "evt_#{rand(99999)}", text: text, author: author,
      thread_id: thread_id, channel_id: channel_id, platform: adapter_name)
    ChatSDK::Events::Mention.new(
      message: message, thread_id: thread_id, channel_id: channel_id,
      platform: adapter_name, adapter_name: adapter_name
    )
  end

  it "same handler fires for mentions from different adapters" do
    received = []
    bot.on_new_mention { |_thread, msg| received << [msg.platform, msg.text] }

    bot.dispatch(build_mention(text: "from slack", adapter_name: :slack), adapter_name: :slack)
    bot.dispatch(build_mention(text: "from teams", adapter_name: :teams, channel_id: "C2"), adapter_name: :teams)

    expect(received.size).to eq(2)
    expect(received[0][1]).to eq("from slack")
    expect(received[1][1]).to eq("from teams")
  end

  it "posts to specific adapter via escape hatch" do
    bot.adapter(:slack).post_message(
      channel_id: "C1",
      message: ChatSDK::PostableMessage.new(text: "slack only")
    )

    expect(slack.posted_messages.size).to eq(1)
    expect(teams.posted_messages.size).to eq(0)
  end

  it "opens DM on specific adapter" do
    channel = bot.open_dm("U123", adapter_name: :teams)
    channel.post("hello DM")

    expect(teams.dm_channels.size).to eq(1)
    expect(teams.posted_messages.size).to eq(1)
    expect(slack.posted_messages.size).to eq(0)
  end
end
