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

  it "renders styled text, card links, and header images" do
    card = ChatSDK.card(title: "Incident", image_url: "https://example.com/header.png") do
      text "Quiet note", style: :muted
      text "Important", style: :bold
      link url: "https://example.com/details", label: "Details"
    end

    blocks = renderer.render(card)

    expect(blocks[1]).to eq(
      type: "image",
      image_url: "https://example.com/header.png",
      alt_text: "Incident"
    )
    expect(blocks[2]).to eq(
      type: "context",
      elements: [{type: "mrkdwn", text: "Quiet note"}]
    )
    expect(blocks[3].dig(:text, :text)).to eq("*Important*")
    expect(blocks[4].dig(:text, :text)).to eq("<https://example.com/details|Details>")
  end

  it "renders initial and radio selections while ignoring unsupported action attributes" do
    card = ChatSDK.card do
      actions do
        button "Disabled", id: "disabled", disabled: true
        link_button "Primary link", url: "https://example.com", style: :primary
        select id: "choice", label: "Choice", initial_option: "a", dispatch_action: true do
          option "A", value: "a"
          option "B", value: "b"
        end
        radio_select id: "radio", label: "Radio", initial_option: "9" do
          12.times { |index| option "Option #{index}", value: index.to_s }
        end
      end
    end

    elements = renderer.render(card).first[:elements]

    expect(elements[0]).not_to have_key(:disabled)
    expect(elements[1][:style]).to eq("primary")
    expect(elements[2][:initial_option]).to eq(elements[2][:options][0])
    expect(elements[2]).not_to have_key(:dispatch_action)
    expect(elements[3][:type]).to eq("radio_buttons")
    expect(elements[3][:options].size).to eq(10)
    expect(elements[3][:initial_option][:value]).to eq("9")
  end

  it "renders section links alongside text in child order" do
    card = ChatSDK.card do
      section do
        text "Before"
        link url: "https://example.com/docs", label: "Docs"
        text "After"
      end
    end

    expect(renderer.render(card).first).to eq(
      type: "section",
      text: {type: "mrkdwn", text: "Before\n<https://example.com/docs|Docs>\nAfter"}
    )
  end
end
