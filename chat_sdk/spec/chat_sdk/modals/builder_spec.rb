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

    it "builds with submit_label, close_label, and callback_id" do
      builder = described_class.new(title: "Form", submit_label: "Submit", close_label: "Back", callback_id: "form:1")
      modal = builder.build
      expect(modal.attributes[:submit_label]).to eq("Submit")
      expect(modal.attributes[:close_label]).to eq("Back")
      expect(modal.attributes[:callback_id]).to eq("form:1")
    end

    it "builds with text_input" do
      builder = described_class.new(title: "Form") do
        text_input id: "name", label: "Name", placeholder: "Enter name", initial_value: "Ada", max_length: 50
      end
      modal = builder.build
      input = modal.children.first
      expect(input.type).to eq(:input)
      expect(input.attributes[:id]).to eq("name")
      expect(input.attributes[:label]).to eq("Name")
      expect(input.attributes[:input_type]).to eq(:text)
      expect(input.attributes[:multiline]).to be false
      expect(input.attributes[:placeholder]).to eq("Enter name")
      expect(input.attributes[:initial_value]).to eq("Ada")
      expect(input.attributes[:max_length]).to eq(50)
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
        select_input id: "priority", label: "Priority", placeholder: "Choose", initial_option: "high", dispatch_action: true do
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
      expect(select.attributes).to include(initial_option: "high", dispatch_action: true)
    end

    it "builds radio and external select inputs" do
      modal = described_class.new(title: "Form") do
        radio_select_input id: "scope", label: "Scope", initial_option: "team", optional: true, dispatch_action: true do
          option "Team", value: "team"
          option "Personal", value: "personal"
        end
        external_select_input(
          id: "owner",
          label: "Owner",
          placeholder: "Search people",
          min_query_length: 2,
          initial_option: {label: "Ada", value: "ada", description: "Engineer"},
          optional: true
        )
      end.build

      radio, external = modal.children
      expect(radio.attributes).to include(
        input_type: :radio_select, initial_option: "team", optional: true, dispatch_action: true
      )
      expect(radio.children.size).to eq(2)
      expect(external.attributes).to include(
        input_type: :external_select,
        min_query_length: 2,
        initial_option: {label: "Ada", value: "ada", description: "Engineer"},
        optional: true
      )
    end

    it "builds fields and rejects select inputs without options" do
      modal = described_class.new(title: "Form") do
        fields do
          field "Team", "Platform"
        end
      end.build
      expect(modal.children.first.type).to eq(:fields)
      expect(modal.children.first.children.first.attributes).to include(label: "Team", value: "Platform")

      expect do
        described_class.new(title: "Form") { select_input(id: "empty", label: "Empty") {} }
      end.to raise_error(ArgumentError, "Select requires at least one option")
      expect do
        described_class.new(title: "Form") { radio_select_input(id: "empty", label: "Empty") {} }
      end.to raise_error(ArgumentError, "RadioSelect requires at least one option")
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

    it "builds date and number inputs" do
      modal = described_class.new(title: "Schedule") do
        date_input id: "due", label: "Due date", initial_value: "2026-09-12"
        number_input id: "count", label: "Count", min: 1, max: 10, initial_value: 2
      end.build

      expect(modal.children[0].attributes).to include(
        id: "due", input_type: :date, initial_value: "2026-09-12"
      )
      expect(modal.children[1].attributes).to include(
        id: "count", input_type: :number, min: 1, max: 10, initial_value: 2
      )
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
