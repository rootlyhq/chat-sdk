# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::WhatsApp::FormatConverter do
  subject(:converter) { described_class.new }

  describe "#from_markdown" do
    it "converts bold from double to single asterisks" do
      expect(converter.from_markdown("**bold**")).to eq("*bold*")
    end

    it "converts italic from asterisks to underscores" do
      expect(converter.from_markdown("*italic*")).to eq("_italic_")
    end

    it "converts strikethrough from double to single tildes" do
      expect(converter.from_markdown("~~strike~~")).to eq("~strike~")
    end

    it "preserves inline code" do
      expect(converter.from_markdown("`code`")).to eq("`code`")
    end

    it "preserves code blocks" do
      input = "```ruby\nputs 'hi'\n```"
      expect(converter.from_markdown(input)).to eq(input)
    end

    it "returns plain text unchanged" do
      expect(converter.from_markdown("Hello world")).to eq("Hello world")
    end

    it "returns empty string for nil" do
      expect(converter.from_markdown(nil)).to eq("")
    end

    it "returns empty string for empty string" do
      expect(converter.from_markdown("")).to eq("")
    end
  end

  describe "#to_markdown" do
    it "converts bold from single to double asterisks" do
      expect(converter.to_markdown("*bold*")).to eq("**bold**")
    end

    it "converts italic from underscores to asterisks" do
      expect(converter.to_markdown("_italic_")).to eq("*italic*")
    end

    it "converts strikethrough from single to double tildes" do
      expect(converter.to_markdown("~strike~")).to eq("~~strike~~")
    end

    it "returns plain text unchanged" do
      expect(converter.to_markdown("Hello world")).to eq("Hello world")
    end

    it "returns empty string for nil" do
      expect(converter.to_markdown(nil)).to eq("")
    end

    it "returns empty string for empty string" do
      expect(converter.to_markdown("")).to eq("")
    end
  end
end
