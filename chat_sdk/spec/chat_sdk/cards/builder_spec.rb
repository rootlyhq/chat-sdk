# frozen_string_literal: true

require_relative "../../../../spec/spec_helper"

RSpec.describe ChatSDK::Cards::Builder do
  describe "building cards" do
    it "builds a basic card" do
      card = ChatSDK.card(title: "Test", subtitle: "Sub") do
        text "Hello world"
      end
      expect(card.type).to eq(:card)
      expect(card.attributes[:title]).to eq("Test")
      expect(card.children.size).to eq(1)
      expect(card.children.first.type).to eq(:text)
    end

    it "builds an image header, styled text, and a card link" do
      card = ChatSDK.card(title: "Test", image_url: "https://example.com/header.png") do
        text "Important", style: :bold
        text "Note", style: :muted
        link url: "https://example.com", label: "Visit"
      end

      expect(card.attributes[:image_url]).to eq("https://example.com/header.png")
      expect(card.children.map { |child| child.attributes[:style] }).to eq([:bold, :muted, nil])
      expect(card.children.last).to have_attributes(
        type: :link,
        attributes: {url: "https://example.com", label: "Visit"}
      )
      expect(card.fallback_text).to include("Visit (https://example.com)")
    end

    it "builds with fields" do
      card = ChatSDK.card(title: "Test") do
        fields do
          field "Name", "Bot"
          field "Status", "Online"
        end
      end
      fields_node = card.children.first
      expect(fields_node.type).to eq(:fields)
      expect(fields_node.children.size).to eq(2)
      expect(fields_node.children.first.attributes[:label]).to eq("Name")
    end

    it "builds with actions" do
      card = ChatSDK.card(title: "Test") do
        actions do
          button "Click", id: "btn:1", style: :primary, value: "v1"
          link_button "Link", url: "https://example.com"
          select id: "sel:1", placeholder: "Pick" do
            option "A", value: "a"
            option "B", value: "b", description: "Second"
          end
        end
      end
      actions_node = card.children.first
      expect(actions_node.type).to eq(:actions)
      expect(actions_node.children.size).to eq(3)

      btn = actions_node.children[0]
      expect(btn.type).to eq(:button)
      expect(btn.attributes[:id]).to eq("btn:1")
      expect(btn.attributes[:style]).to eq(:primary)

      sel = actions_node.children[2]
      expect(sel.type).to eq(:select)
      expect(sel.children.size).to eq(2)
    end

    it "builds with divider and image" do
      card = ChatSDK.card(title: "Test") do
        divider
        image url: "https://example.com/img.png", alt: "Chart"
      end
      expect(card.children[0].type).to eq(:divider)
      expect(card.children[1].type).to eq(:image)
      expect(card.children[1].attributes[:url]).to eq("https://example.com/img.png")
    end

    it "builds with sections" do
      card = ChatSDK.card(title: "Test") do
        section "Details" do
          text "Some detail"
        end
      end
      section = card.children.first
      expect(section.type).to eq(:section)
      expect(section.attributes[:title]).to eq("Details")
      expect(section.children.first.attributes[:content]).to eq("Some detail")
    end

    it "generates fallback text" do
      card = ChatSDK.card(title: "Alert") do
        text "Server down"
        fields do
          field "Service", "api"
        end
      end
      expect(card.fallback_text).to include("Server down")
      expect(card.fallback_text).to include("Service: api")
    end

    it "builds tables and charts with fallback text" do
      card = ChatSDK.card(title: "Metrics", width: :full) do
        table headers: ["Service", "Status"], rows: [["api", "healthy"]]
        chart title: "Traffic", type: :pie, segments: [{label: "API", value: 42}]
      end

      expect(card.attributes[:width]).to eq(:full)
      expect(card.children.map(&:type)).to eq(%i[table chart])
      expect(card.fallback_text).to include("Service | Status")
      expect(card.fallback_text).to include("API: 42")
    end

    it "keeps button tooltips" do
      card = ChatSDK.card do
        actions do
          button "Approve", id: "approve", tooltip: "Approve the request", disabled: true
          link_button "Details", url: "https://example.com", style: :primary
        end
      end

      expect(card.children.first.children.first.attributes[:tooltip]).to eq("Approve the request")
      expect(card.children.first.children.first.attributes[:disabled]).to be(true)
      expect(card.children.first.children.last.attributes[:style]).to eq(:primary)
    end

    it "builds selects with initial values and radio selects" do
      card = ChatSDK.card do
        actions do
          select id: "status", label: "Status", initial_option: "open", optional: true, dispatch_action: true do
            option "Open", value: "open"
          end
          radio_select id: "priority", label: "Priority", initial_option: "high", optional: true do
            option "High", value: "high"
          end
        end
      end

      select, radio = card.children.first.children
      expect(select.attributes).to include(
        label: "Status", initial_option: "open", optional: true, dispatch_action: true
      )
      expect(radio.type).to eq(:radio_select)
      expect(radio.attributes).to include(label: "Priority", initial_option: "high", optional: true)
    end

    it "requires options for select and radio select actions" do
      expect { ChatSDK.card { actions { select(id: "empty") {} } } }
        .to raise_error(ArgumentError, "Select requires at least one option")
      expect { ChatSDK.card { actions { radio_select(id: "empty", label: "Empty") {} } } }
        .to raise_error(ArgumentError, "RadioSelect requires at least one option")
    end

    it "builds text inputs as card children" do
      card = ChatSDK.card do
        text_input id: "name", label: "Your name", placeholder: "Enter a name", optional: true, max_length: 100
      end

      expect(card.children.first.type).to eq(:text_input)
      expect(card.children.first.attributes).to include(
        id: "name", label: "Your name", placeholder: "Enter a name", optional: true, max_length: 100
      )
      expect(card.fallback_text).to eq("Your name")
      expect(ChatSDK::Cards::Renderer.new.render(card)).to include("Your name")
    end

    it "rejects Teams-reserved text input ids and preserves empty values" do
      %w[actionId value msteams].each do |id|
        expect { ChatSDK.card { text_input(id: id, label: "Reserved") } }
          .to raise_error(ArgumentError, /reserved/)
      end

      card = ChatSDK.card do
        text_input id: "name", label: "Name", value: ""
      end

      expect(card.children.first.attributes[:value]).to eq("")
    end

    it "stores native table rendering options" do
      card = ChatSDK.card do
        table headers: ["Name"], rows: [["Ada"]], widths: [2], grid_lines: false,
          grid_style: :accent, vertical_align: :center
      end

      expect(card.children.first.attributes).to include(
        widths: [2],
        grid_lines: false,
        grid_style: :accent,
        vertical_align: :center
      )
    end

    it "stores visible user IDs on buttons" do
      card = ChatSDK.card do
        actions { button "Approve", id: "approve", visible_to: %w[U1 U2] }
      end

      expect(card.children.first.children.first.attributes[:visible_to]).to eq(%w[U1 U2])
    end
  end
end
