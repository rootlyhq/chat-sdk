# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

RSpec.describe ChatSDK::Format::Mentions do
  describe ".mask_code_spans" do
    it "masks inline code while preserving surrounding text" do
      expect(described_class.mask_code_spans("before `@bot` after")).to eq("before        after")
    end

    it "masks fenced code while preserving line breaks" do
      expect(described_class.mask_code_spans("before ```\n@bot\n``` after")).to eq("before    \n    \n    after")
    end

    it "leaves an unclosed single backtick run literal" do
      expect(described_class.mask_code_spans("it`s @bot help")).to eq("it`s @bot help")
    end

    it "leaves an unclosed fence literal" do
      expect(described_class.mask_code_spans("before ```\n@bot help")).to eq("before ```\n@bot help")
    end

    it "masks inline code spans across line breaks" do
      expect(described_class.mask_code_spans("before `\n@bot\n` after")).to eq("before  \n    \n  after")
    end
  end
end
