# frozen_string_literal: true

require_relative "../../../spec/spec_helper"
require "chat_sdk/slack"
require "chat_sdk/teams"
require "chat_sdk/gchat"
require "chat_sdk/mattermost"

RSpec.describe "Integration: card rendering across platforms" do
  let(:card) do
    ChatSDK.card(title: "Deploy", subtitle: "v2.1.0") do
      text "Deploying *api-service* to production"
      fields do
        field "Service", "api-service"
        field "Version", "2.1.0"
        field "Region", "us-east-1"
      end
      divider
      actions do
        button "Approve", id: "deploy:approve", style: :primary, value: "deploy-123"
        button "Reject", id: "deploy:reject", style: :danger, value: "deploy-123"
        link_button "Diff", url: "https://github.com/org/repo/compare/v2.0.0...v2.1.0"
      end
    end
  end

  describe "Slack Block Kit" do
    let(:renderer) { ChatSDK::Slack::BlockKitRenderer.new }

    it "produces valid Block Kit JSON structure" do
      blocks = renderer.render(card)
      expect(blocks).to be_an(Array)

      types = blocks.map { |b| b[:type] }
      expect(types).to include("section", "divider", "actions")

      actions_block = blocks.find { |b| b[:type] == "actions" }
      expect(actions_block[:elements].size).to eq(3)
      expect(actions_block[:elements][0][:type]).to eq("button")
      expect(actions_block[:elements][0][:style]).to eq("primary")
    end
  end

  describe "Teams Adaptive Card" do
    let(:renderer) { ChatSDK::Teams::AdaptiveCardRenderer.new }

    it "produces valid Adaptive Card JSON structure" do
      result = renderer.render(card)
      expect(result["type"]).to eq("AdaptiveCard")
      expect(result["body"]).to be_an(Array)

      types = result["body"].map { |e| e["type"] }
      expect(types).to include("TextBlock", "FactSet", "ActionSet")
    end
  end

  describe "GChat Card V2" do
    let(:renderer) { ChatSDK::GChat::CardV2Renderer.new }

    it "produces valid Card V2 JSON structure" do
      result = renderer.render(card)
      expect(result).to have_key(:cards_v2)
      expect(result[:cards_v2]).to be_an(Array)

      inner_card = result[:cards_v2].first[:card]
      expect(inner_card).to have_key(:sections)
    end
  end

  describe "Mattermost Attachments" do
    let(:renderer) { ChatSDK::Mattermost::AttachmentRenderer.new }

    it "produces valid message attachment structure" do
      result = renderer.render(card)
      expect(result).to be_an(Array)
      expect(result.first).to have_key("title")
      expect(result.first["title"]).to eq("Deploy")
    end
  end

  describe "fallback markdown renderer" do
    let(:renderer) { ChatSDK::Cards::Renderer.new }

    it "renders readable markdown" do
      md = renderer.render(card)
      expect(md).to include("**Deploy**")
      expect(md).to include("*v2.1.0*")
      expect(md).to include("api-service")
      expect(md).to include("---")
      expect(md).to include("[Approve]")
      expect(md).to include("[Diff](https://github.com/org/repo/compare/v2.0.0...v2.1.0)")
    end
  end

  describe "same card posted to all adapters" do
    it "posts without error through each adapter" do
      fake = ChatSDK::Testing::FakeAdapter.new
      state = ChatSDK::State::Memory.new
      bot = ChatSDK::Chat.new(user_name: "bot", adapters: {test: fake}, state: state)
      thread = ChatSDK::Thread.new(id: "T1", channel_id: "C1", adapter: fake, chat: bot)

      expect { thread.post(card) }.not_to raise_error
      expect(fake.posted_messages.size).to eq(1)
      expect(fake.posted_messages.first[:message].card?).to be true
    end
  end
end
