# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::Twilio::FormatConverter do
  subject(:converter) { described_class.new }

  describe "#from_markdown" do
    it "strips bold markers" do
      expect(converter.from_markdown("**bold**")).to eq("bold")
    end

    it "strips italic markers" do
      expect(converter.from_markdown("*italic*")).to eq("italic")
    end

    it "strips strikethrough markers" do
      expect(converter.from_markdown("~~strike~~")).to eq("strike")
    end

    it "converts links to text with url" do
      expect(converter.from_markdown("[click here](https://example.com)")).to eq("click here (https://example.com)")
    end

    it "strips inline code markers" do
      expect(converter.from_markdown("use `code` here")).to eq("use code here")
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
    it "passes through plain text" do
      expect(converter.to_markdown("Hello world")).to eq("Hello world")
    end
  end
end
