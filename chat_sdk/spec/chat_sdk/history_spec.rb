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
end
