# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::Slack::BlockKitRenderer do
  subject(:renderer) { described_class.new }

  it "truncates card headers to Slack's limit" do
    block = renderer.render(ChatSDK.card(title: "h" * 200)).first

    expect(block.dig(:text, :text).length).to eq(150)
  end

  it "truncates section and context text" do
    card = ChatSDK.card(subtitle: "c" * 3_200) do
      text "s" * 3_200
    end
    blocks = renderer.render(card)

    expect(blocks[0].dig(:elements, 0, :text).length).to eq(3_000)
    expect(blocks[1].dig(:text, :text).length).to eq(3_000)
  end

  it "truncates fields to 2,000 characters" do
    card = ChatSDK.card do
      fields { field "Field", "v" * 3_000 }
    end

    expect(renderer.render(card).first[:fields].first[:text].length).to eq(2_000)
  end

  it "truncates image alt text to 2,000 characters" do
    card = ChatSDK.card do
      image url: "https://example.com/image.png", alt: "a" * 2_500
    end

    expect(renderer.render(card).first[:alt_text].length).to eq(2_000)
  end

  it "truncates button and link labels to 75 characters" do
    card = ChatSDK.card do
      actions do
        button "b" * 100, id: "button"
        link_button "l" * 100, url: "https://example.com"
      end
    end
    elements = renderer.render(card).first[:elements]

    expect(elements.map { |element| element.dig(:text, :text).length }).to eq([75, 75])
  end

  it "renders text-input labels as text and maps visible users to Slack buttons" do
    card = ChatSDK.card do
      text_input id: "name", label: "Your name"
      actions do
        button "Approve", id: "approve", visible_to: ["U1"]
        link_button "Details", url: "https://example.com", visible_to: ["U2"]
      end
    end
    blocks = renderer.render(card)

    expect(blocks[0]).to eq(type: "section", text: {type: "mrkdwn", text: "Your name"})
    expect(blocks[1][:elements].map { |element| element[:visible_to_user_ids] }).to eq([["U1"], ["U2"]])
  end

  it "truncates select placeholders, options, and descriptions" do
    card = ChatSDK.card do
      actions do
        select id: "choice", placeholder: "p" * 200 do
          option "o" * 100, value: "value", description: "d" * 100
        end
      end
    end
    select = renderer.render(card).first[:elements].first

    expect(select.dig(:placeholder, :text).length).to eq(150)
    expect(select.dig(:options, 0, :text, :text).length).to eq(75)
    expect(select.dig(:options, 0, :description, :text).length).to eq(75)
  end

  it "does not split Slack tokens or HTML entities while truncating mrkdwn" do
    card = ChatSDK.card do
      text "#{"a" * 2_997}<@B123>tail"
      text "#{"b" * 2_997}&amp;tail"
    end
    sections = renderer.render(card)

    expect(sections[0].dig(:text, :text)).not_to include("<@")
    expect(sections[1].dig(:text, :text)).not_to end_with("&", "&a", "&am", "&amp")
  end

  it "closes open bold formatting and fenced code after truncation" do
    card = ChatSDK.card do
      text "*#{"b" * 3_200}"
      text "```ruby\n#{"c" * 3_200}"
    end
    sections = renderer.render(card)
    bold = sections[0].dig(:text, :text)
    fence = sections[1].dig(:text, :text)

    expect(bold.length).to be <= 3_000
    expect(bold).to match(/\*…\z/)
    expect(fence.length).to be <= 3_000
    expect(fence).to end_with("\n```")
  end
end
