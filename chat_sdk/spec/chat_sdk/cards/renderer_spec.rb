# frozen_string_literal: true

require_relative "../../../../spec/spec_helper"

RSpec.describe ChatSDK::Cards::Renderer do
  let(:renderer) { described_class.new }

  it "renders card to markdown" do
    card = ChatSDK.card(title: "Alert", subtitle: "SEV1") do
      text "Server down"
      divider
      actions do
        button "Ack", id: "ack", style: :primary
        link_button "Runbook", url: "https://example.com"
      end
    end
    output = renderer.render(card)
    expect(output).to include("**Alert**")
    expect(output).to include("*SEV1*")
    expect(output).to include("Server down")
    expect(output).to include("---")
    expect(output).to include("[Ack]")
    expect(output).to include("[Runbook](https://example.com)")
  end

  it "renders radio selects as fallback text using their label" do
    card = ChatSDK.card do
      actions do
        radio_select id: "priority", label: "Priority" do
          option "High", value: "high"
          option "Low", value: "low"
        end
      end
    end

    expect(renderer.render(card)).to eq("_Priority_")
  end
end
