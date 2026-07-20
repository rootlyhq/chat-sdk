# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::Mattermost::FormatConverter do
  subject(:converter) { described_class.new }

  describe "#to_markdown" do
    it "passes through all formatting unchanged" do
      input = "**bold** *italic* ~~strike~~ `code` [link](https://example.com)"
      expect(converter.to_markdown(input)).to eq(input)
    end

    it "passes through plain text" do
      expect(converter.to_markdown("Hello world")).to eq("Hello world")
    end

    it "passes through code blocks" do
      input = "```ruby\nputs 'hi'\n```"
      expect(converter.to_markdown(input)).to eq(input)
    end
  end

  describe "#from_markdown" do
    it "passes through all formatting unchanged" do
      input = "**bold** *italic* ~~strike~~ `code` [link](https://example.com)"
      expect(converter.from_markdown(input)).to eq(input)
    end

    it "passes through plain text" do
      expect(converter.from_markdown("Hello world")).to eq("Hello world")
    end
  end
end
