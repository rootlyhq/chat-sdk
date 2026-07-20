# frozen_string_literal: true

require_relative "../../../../spec/spec_helper"

RSpec.describe ChatSDK::Format::Converter do
  subject(:converter) { described_class.new }

  describe "#to_markdown" do
    it "returns the input unchanged" do
      expect(converter.to_markdown("hello world")).to eq("hello world")
    end

    it "passes through markdown formatting" do
      expect(converter.to_markdown("**bold** and *italic*")).to eq("**bold** and *italic*")
    end
  end

  describe "#from_markdown" do
    it "returns the input unchanged" do
      expect(converter.from_markdown("hello world")).to eq("hello world")
    end

    it "passes through markdown formatting" do
      expect(converter.from_markdown("**bold** and *italic*")).to eq("**bold** and *italic*")
    end
  end

  describe "#parse" do
    it "returns a commonmarker node" do
      node = converter.parse("# Hello")
      expect(node).not_to be_nil
    end
  end

  describe "#render_markdown" do
    it "renders a parsed node back to commonmark" do
      node = converter.parse("**bold**")
      result = converter.render_markdown(node)
      expect(result.strip).to eq("**bold**")
    end
  end

  describe "#render_html" do
    it "renders a parsed node to HTML" do
      node = converter.parse("**bold**")
      result = converter.render_html(node)
      expect(result.strip).to eq("<p><strong>bold</strong></p>")
    end
  end
end
