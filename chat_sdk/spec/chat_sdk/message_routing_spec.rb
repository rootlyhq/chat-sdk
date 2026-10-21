# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

RSpec.describe "message routing" do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }
  let(:chat) { ChatSDK::Chat.new(user_name: "test-bot", adapters: {test: adapter}, state: state) }

  def message_event(type:, text:, is_mention: nil, message_id: "M1", attachments: [])
    message = ChatSDK::Message.new(
      id: message_id,
      text: text,
      author: ChatSDK::Author.new(id: "U1", name: "user", platform: :test),
      thread_id: "T1",
      channel_id: "C1",
      platform: :test,
      is_mention: is_mention,
      attachments: attachments
    )
    event_class = {
      mention: ChatSDK::Events::Mention,
      subscribed_message: ChatSDK::Events::SubscribedMessage,
      direct_message: ChatSDK::Events::DirectMessage
    }.fetch(type)
    event_class.new(
      message: message, thread_id: "T1", channel_id: "C1",
      platform: :test, adapter_name: :test
    )
  end

  it "routes pattern matches and attachment-only messages to new-message handlers" do
    calls = []
    chat.on_new_message(/deploy/) { |_thread, message| calls << message.text }
    chat.on_new_message { |_thread, message| calls << :all }

    chat.dispatch(message_event(type: :subscribed_message, text: "deploy"), adapter_name: :test)
    chat.dispatch(
      message_event(type: :subscribed_message, text: "", message_id: "M2", attachments: [{name: "report.pdf"}]),
      adapter_name: :test
    )

    expect(calls).to eq(["deploy", :all, :all])
  end

  it "detects mentions outside code, case-insensitively" do
    mentions = []
    chat.on_new_mention { |_thread, message| mentions << message.text }
    chat.on_new_message { |_thread, message| mentions << :new_message }

    ["@TEST-BOT hello", "`@test-bot`", "```\n@test-bot\n```"].each_with_index do |text, index|
      chat.dispatch(message_event(type: :subscribed_message, text: text, message_id: "M#{index}"), adapter_name: :test)
    end

    expect(mentions).to eq(["@TEST-BOT hello", :new_message, :new_message])
  end

  it "does not override an adapter's definitive false mention flag" do
    calls = []
    chat.on_new_mention { |_thread, _message| calls << :mention }
    chat.on_new_message { |_thread, _message| calls << :new_message }

    chat.dispatch(message_event(type: :subscribed_message, text: "@test-bot", is_mention: false), adapter_name: :test)

    expect(calls).to eq([:new_message])
  end

  it "routes DMs to DM handlers before mention handlers" do
    calls = []
    chat.on_direct_message { |_thread, _message| calls << :dm }
    chat.on_new_mention { |_thread, _message| calls << :mention }

    chat.dispatch(message_event(type: :direct_message, text: "hello"), adapter_name: :test)

    expect(calls).to eq([:dm])
  end

  it "treats a DM without a DM handler as a mention" do
    mention_flag = nil
    chat.on_new_mention { |_thread, message| mention_flag = message.is_mention }

    chat.dispatch(message_event(type: :direct_message, text: "hello"), adapter_name: :test)

    expect(mention_flag).to be(true)
  end

  it "routes subscribed threads before mention handlers" do
    calls = []
    chat.on_subscribed_message { |_thread, _message| calls << :subscribed }
    chat.on_new_mention { |_thread, _message| calls << :mention }
    state.subscribe("test:C1:T1")

    chat.dispatch(message_event(type: :subscribed_message, text: "@test-bot"), adapter_name: :test)

    expect(calls).to eq([:subscribed])
  end
end
