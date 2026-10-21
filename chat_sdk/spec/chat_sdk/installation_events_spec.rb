# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

RSpec.describe "installation lifecycle events" do
  let(:adapter) do
    Class.new(ChatSDK::Adapter::Base) do
      def name = :teams
    end.new
  end
  let(:chat) do
    ChatSDK::Chat.new(user_name: "bot", adapters: {teams: adapter}, state: ChatSDK::State::Memory.new)
  end

  it "dispatches installed events to on_installed handlers" do
    event = ChatSDK::Events::Installed.new(
      conversation_id: "conversation-1",
      action: "add",
      platform: :teams,
      adapter_name: :teams
    )
    received = nil
    chat.on_installed { |installed| received = installed }

    chat.dispatch(event, adapter_name: :teams)

    expect(received).to be(event)
  end

  it "dispatches uninstalled events to on_uninstalled handlers" do
    event = ChatSDK::Events::Uninstalled.new(
      conversation_id: "conversation-1",
      action: "remove-upgrade",
      platform: :teams,
      adapter_name: :teams
    )
    received = nil
    chat.on_uninstalled { |uninstalled| received = uninstalled }

    chat.dispatch(event, adapter_name: :teams)

    expect(received).to be(event)
  end
end
