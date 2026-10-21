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

    it "masks an unclosed code span" do
      expect(described_class.mask_code_spans("before `@bot")).to eq("before      ")
    end

    it "masks inline code spans across line breaks" do
      expect(described_class.mask_code_spans("before `\n@bot\n` after")).to eq("before  \n    \n  after")
    end
  end
end
