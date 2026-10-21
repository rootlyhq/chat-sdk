# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::GitLab::CardRenderer do
  subject(:renderer) { described_class.new }

  it "renders card headings and children as GitLab Markdown" do
    card = ChatSDK.card(title: "Deploy [42]", subtitle: "production") do
      text "Deploy now"
      divider
      image(url: "https://example.test/image (1).png", alt: "screenshot")
    end

    expect(renderer.render(card)).to eq(
      "**Deploy \\[42\\]**\nproduction\n\nDeploy now\n\n---\n\n![screenshot](https://example.test/image%20%281%29.png)"
    )
  end

  it "renders fields, actions, and tables as fallback Markdown" do
    card = ChatSDK.card do
      fields do
        field "Region", "us-west"
      end
      actions do
        link_button "Open", url: "https://example.test/issues/1"
      end
      table headers: ["Name", "Value"], rows: [["zone", "us|west"]], align: [:left, :right]
    end

    expect(renderer.render(card)).to eq(
      "**Region:** us-west\n\n[Open](https://example.test/issues/1)\n\n| Name | Value |\n| --- | ---: |\n| zone | us\\|west |"
    )
  end

  it "falls back to a card node's text for unsupported elements" do
    card = ChatSDK.card do
      chart title: "Traffic", type: :bar, series: [{name: "Requests", data: []}]
    end

    expect(renderer.render(card)).to eq("Traffic\nRequests:")
  end
end
