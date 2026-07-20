# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::Discord::FormatConverter do
  subject(:converter) { described_class.new }

  describe "#to_markdown" do
    context "mentions" do
      it "converts user mention to plain @id" do
        expect(converter.to_markdown("<@123456>")).to eq("@123456")
      end

      it "converts nickname mention to plain @id" do
        expect(converter.to_markdown("<@!123456>")).to eq("@123456")
      end

      it "converts channel mention to plain #id" do
        expect(converter.to_markdown("<#789012>")).to eq("#789012")
      end
    end

    context "custom emoji" do
      it "converts custom emoji to shortcode" do
        expect(converter.to_markdown("<:fire:123>")).to eq(":fire:")
      end

      it "converts animated emoji to shortcode" do
        expect(converter.to_markdown("<a:dance:456>")).to eq(":dance:")
      end

      it "handles emoji with underscores in name" do
        expect(converter.to_markdown("<:thumbs_up:789>")).to eq(":thumbs_up:")
      end
    end

    context "spoilers" do
      it "strips spoiler markers" do
        expect(converter.to_markdown("||secret||")).to eq("secret")
      end

      it "strips spoiler with formatted content" do
        expect(converter.to_markdown("||**bold secret**||")).to eq("**bold secret**")
      end

      it "handles multiple spoilers" do
        expect(converter.to_markdown("||one|| and ||two||")).to eq("one and two")
      end
    end

    context "standard markdown pass-through" do
      it "preserves bold" do
        expect(converter.to_markdown("**bold**")).to eq("**bold**")
      end

      it "preserves italic" do
        expect(converter.to_markdown("*italic*")).to eq("*italic*")
      end

      it "preserves strikethrough" do
        expect(converter.to_markdown("~~strike~~")).to eq("~~strike~~")
      end

      it "preserves inline code" do
        expect(converter.to_markdown("`code`")).to eq("`code`")
      end

      it "preserves code blocks" do
        input = "```ruby\nputs 'hi'\n```"
        expect(converter.to_markdown(input)).to eq(input)
      end
    end

    context "mixed content" do
      it "converts all Discord syntax in one message" do
        input = "Hello <@123>, check <#456> and <:thumbsup:789>"
        expect(converter.to_markdown(input)).to eq("Hello @123, check #456 and :thumbsup:")
      end

      it "handles mentions alongside markdown formatting" do
        input = "**Important:** <@999> please review"
        expect(converter.to_markdown(input)).to eq("**Important:** @999 please review")
      end
    end

    context "edge cases" do
      it "returns empty string for nil" do
        expect(converter.to_markdown(nil)).to eq("")
      end

      it "returns empty string for empty string" do
        expect(converter.to_markdown("")).to eq("")
      end

      it "returns plain text unchanged" do
        expect(converter.to_markdown("Hello world")).to eq("Hello world")
      end

      it "does not strip URLs in angle brackets" do
        expect(converter.to_markdown("<https://example.com>")).to eq("<https://example.com>")
      end
    end
  end

  describe "#from_markdown" do
    it "passes through standard markdown formatting" do
      input = "**bold** *italic* ~~strike~~ `code`"
      expect(converter.from_markdown(input)).to eq(input)
    end

    it "passes through plain text" do
      expect(converter.from_markdown("Hello world")).to eq("Hello world")
    end

    it "returns empty string for nil" do
      expect(converter.from_markdown(nil)).to eq("")
    end

    it "returns empty string for empty string" do
      expect(converter.from_markdown("")).to eq("")
    end
  end

  describe "round-trip" do
    it "preserves standard markdown through Discord→md→Discord" do
      markdown = "**bold** *italic* ~~strike~~ `code`"
      converted = converter.to_markdown(markdown)
      round_tripped = converter.from_markdown(converted)
      expect(round_tripped).to eq(markdown)
    end

    it "normalizes mentions (one-way)" do
      discord_text = "Hello <@123>"
      markdown = converter.to_markdown(discord_text)
      expect(markdown).to eq("Hello @123")
      # Can't restore <@id> from @id — this is expected
      expect(converter.from_markdown(markdown)).to eq("Hello @123")
    end
  end
end
