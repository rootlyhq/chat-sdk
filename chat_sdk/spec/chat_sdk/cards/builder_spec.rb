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
  end
end
