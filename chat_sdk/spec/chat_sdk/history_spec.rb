# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

RSpec.describe ChatSDK::History do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }
  let(:bot) do
    ChatSDK::Chat.new(
      user_name: "test-bot",
      adapters: {test: adapter},
      state: state,
      history: {user: {max_per_user: 2}}
    )
  end
  let(:thread) { bot.thread("T1", channel_id: "C1") }

  def message(id, text, email: "person@example.com")
    ChatSDK::Message.new(
      id: id,
      text: text,
      author: ChatSDK::Author.new(id: "U1", name: "Person", email: email, platform: :test),
      thread_id: "T1",
      channel_id: "C1",
      platform: :test,
      timestamp: Time.utc(2026, 9, 12)
    )
  end

  it "stores bounded user history and converts it to prompt entries" do
    bot.history.user.append(thread, message("M1", "one"))
    bot.history.user.append(thread, message("M2", "two"))
    bot.history.user.append(thread, message("M3", "three"))

    entries = bot.history.user.list(user_key: "person@example.com")

    expect(entries.map { |entry| entry["text"] }).to eq(%w[two three])
    expect(entries.last["id"]).not_to eq("M3")
    expect(entries.last["platform_message_id"]).to eq("M3")
    expect(bot.history.user.count(user_key: "person@example.com")).to eq(2)
    expect(bot.history.user.to_prompt_entries(entries)).to eq([
      {role: "user", content: "two"},
      {role: "user", content: "three"}
    ])
  end

  it "deletes all history for an identity" do
    bot.history.user.append(thread, message("M1", "one"))

    expect(bot.history.user.delete(user_key: "person@example.com")).to eq({deleted: 1})
    expect(bot.history.user.list(user_key: "person@example.com")).to be_empty
  end

  it "supports uncapped per-user retention" do
    uncapped = ChatSDK::Chat.new(
      user_name: "test-bot",
      adapters: {test: adapter},
      state: state,
      history: {user: {max_per_user: false}}
    )
    uncapped_thread = uncapped.thread("T1", channel_id: "C1")

    205.times { |index| uncapped.history.user.append(uncapped_thread, message("M#{index}", index.to_s)) }

    expect(uncapped.history.user.count(user_key: "person@example.com")).to eq(205)
    expect(uncapped.history.user.list(user_key: "person@example.com").length).to eq(50)
    expect(uncapped.history.user.list(user_key: "person@example.com", limit: nil).length).to eq(205)
  end
end
