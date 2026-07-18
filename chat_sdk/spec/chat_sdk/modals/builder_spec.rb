# frozen_string_literal: true

require_relative "../../../../spec/spec_helper"

RSpec.describe ChatSDK::Modals::Builder do
  describe "building modals" do
    it "builds a modal with title" do
      builder = described_class.new(title: "My Modal")
      modal = builder.build
      expect(modal.type).to eq(:modal)
      expect(modal.attributes[:title]).to eq("My Modal")
    end

    it "builds with submit_label and callback_id" do
      builder = described_class.new(title: "Form", submit_label: "Submit", callback_id: "form:1")
      modal = builder.build
      expect(modal.attributes[:submit_label]).to eq("Submit")
      expect(modal.attributes[:callback_id]).to eq("form:1")
    end

    it "builds with text_input" do
      builder = described_class.new(title: "Form") do
        text_input id: "name", label: "Name", placeholder: "Enter name"
      end
      modal = builder.build
      input = modal.children.first
      expect(input.type).to eq(:input)
      expect(input.attributes[:id]).to eq("name")
      expect(input.attributes[:label]).to eq("Name")
      expect(input.attributes[:input_type]).to eq(:text)
      expect(input.attributes[:multiline]).to be false
      expect(input.attributes[:placeholder]).to eq("Enter name")
    end

    it "builds with multiline text_input" do
      builder = described_class.new(title: "Form") do
        text_input id: "desc", label: "Description", multiline: true
      end
      modal = builder.build
      input = modal.children.first
      expect(input.attributes[:multiline]).to be true
    end

    it "builds with select_input and options" do
      builder = described_class.new(title: "Form") do
        select_input id: "priority", label: "Priority", placeholder: "Choose" do
          option "High", value: "high"
          option "Low", value: "low", description: "Not urgent"
        end
      end
      modal = builder.build
      select = modal.children.first
      expect(select.type).to eq(:input)
      expect(select.attributes[:input_type]).to eq(:select)
      expect(select.attributes[:placeholder]).to eq("Choose")
      expect(select.children.size).to eq(2)
      expect(select.children.first.attributes[:text]).to eq("High")
      expect(select.children.first.attributes[:value]).to eq("high")
      expect(select.children.last.attributes[:description]).to eq("Not urgent")
    end

    it "builds with static_text" do
      builder = described_class.new(title: "Info") do
        static_text "Read the instructions carefully."
      end
      modal = builder.build
      text_node = modal.children.first
      expect(text_node.type).to eq(:text)
      expect(text_node.attributes[:content]).to eq("Read the instructions carefully.")
    end

    it "builds a complex modal with multiple inputs" do
      builder = described_class.new(title: "Incident", submit_label: "Create", callback_id: "incident:create") do
        static_text "Fill out the form below."
        text_input id: "title", label: "Title"
        text_input id: "description", label: "Description", multiline: true, optional: true
        select_input id: "severity", label: "Severity" do
          option "SEV1", value: "1"
          option "SEV2", value: "2"
        end
      end
      modal = builder.build
      expect(modal.children.size).to eq(4)
      expect(modal.children[0].type).to eq(:text)
      expect(modal.children[1].type).to eq(:input)
      expect(modal.children[1].attributes[:id]).to eq("title")
      expect(modal.children[2].attributes[:optional]).to be true
      expect(modal.children[3].attributes[:input_type]).to eq(:select)
    end
  end
end
