# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::Telegram::FormatConverter do
  subject(:converter) { described_class.new }

  describe "#to_markdown" do
    context "unescaping special characters" do
      it "unescapes period" do
        expect(converter.to_markdown('hello\.')).to eq("hello.")
      end

      it "unescapes exclamation mark" do
        expect(converter.to_markdown('wow\!')).to eq("wow!")
      end

      it "unescapes asterisk" do
        expect(converter.to_markdown('\*not bold\*')).to eq("*not bold*")
      end

      it "unescapes hyphen" do
        expect(converter.to_markdown('one \- two')).to eq("one - two")
      end

      it "unescapes multiple special chars" do
        expect(converter.to_markdown('hello\, world\!')).to eq("hello, world!")
      end

      it "unescapes parentheses" do
        expect(converter.to_markdown('test\(1\)')).to eq("test(1)")
      end

      it "unescapes hash" do
        expect(converter.to_markdown('\#heading')).to eq("#heading")
      end

      it "unescapes plus" do
        expect(converter.to_markdown('1 \+ 2')).to eq("1 + 2")
      end

      it "unescapes equals" do
        expect(converter.to_markdown('a \= b')).to eq("a = b")
      end

      it "unescapes pipe" do
        expect(converter.to_markdown('a \| b')).to eq("a | b")
      end

      it "unescapes curly braces" do
        expect(converter.to_markdown('\{code\}')).to eq("{code}")
      end

      it "unescapes backslash" do
        expect(converter.to_markdown('path\\\\dir')).to eq('path\\dir')
      end
    end

    context "underline markers" do
      it "strips underline markers" do
        expect(converter.to_markdown("__underlined__")).to eq("underlined")
      end

      it "strips underline with surrounding text" do
        expect(converter.to_markdown("this is __underlined__ text")).to eq("this is underlined text")
      end
    end

    context "spoiler markers" do
      it "strips spoiler markers" do
        expect(converter.to_markdown("||hidden||")).to eq("hidden")
      end

      it "strips spoiler with surrounding text" do
        expect(converter.to_markdown("this is ||secret|| info")).to eq("this is secret info")
      end
    end

    context "Telegram user links" do
      it "converts user link to @id" do
        expect(converter.to_markdown("[Alice](tg://user?id=123)")).to eq("@123")
      end

      it "converts user link with different name" do
        expect(converter.to_markdown("[Bob](tg://user?id=456789)")).to eq("@456789")
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

      it "preserves standard links" do
        expect(converter.to_markdown("[text](https://example.com)")).to eq("[text](https://example.com)")
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
    end
  end

  describe "#from_markdown" do
    context "escaping special characters" do
      it "escapes period" do
        expect(converter.from_markdown("hello.")).to eq('hello\.')
      end

      it "escapes exclamation mark" do
        expect(converter.from_markdown("wow!")).to eq('wow\!')
      end

      it "escapes hyphen" do
        expect(converter.from_markdown("one - two")).to eq('one \- two')
      end

      it "escapes hash" do
        expect(converter.from_markdown("# heading")).to eq('\# heading')
      end

      it "escapes plus" do
        expect(converter.from_markdown("1 + 2")).to eq('1 \+ 2')
      end

      it "escapes equals" do
        expect(converter.from_markdown("a = b")).to eq('a \= b')
      end

      it "escapes parentheses in plain text" do
        expect(converter.from_markdown("test(1)")).to eq('test\(1\)')
      end
    end

    context "preserving markdown syntax" do
      it "preserves bold markers" do
        expect(converter.from_markdown("**bold**")).to eq("**bold**")
      end

      it "preserves italic markers" do
        expect(converter.from_markdown("*italic*")).to eq("*italic*")
      end

      it "preserves strikethrough markers" do
        expect(converter.from_markdown("~~strike~~")).to eq("~~strike~~")
      end

      it "preserves links" do
        expect(converter.from_markdown("[text](https://example.com)")).to eq("[text](https://example.com)")
      end
    end

    context "code blocks are not escaped" do
      it "does not escape inside inline code" do
        expect(converter.from_markdown("use `foo.bar!` here")).to eq("use `foo.bar!` here")
      end

      it "does not escape inside fenced code blocks" do
        input = "text.\n```\ncode.here!\n```\nmore."
        result = converter.from_markdown(input)
        expect(result).to include("```\ncode.here!\n```")
        expect(result).to start_with('text\.')
        expect(result).to end_with('more\.')
      end
    end

    context "mixed text with special chars" do
      it "escapes special chars in plain text around formatting" do
        result = converter.from_markdown("Hello. **bold** world!")
        expect(result).to eq('Hello\. **bold** world\!')
      end
    end

    context "edge cases" do
      it "returns empty string for nil" do
        expect(converter.from_markdown(nil)).to eq("")
      end

      it "returns empty string for empty string" do
        expect(converter.from_markdown("")).to eq("")
      end

      it "returns escaped text for plain text with no special chars" do
        expect(converter.from_markdown("hello world")).to eq("hello world")
      end
    end
  end

  describe "round-trip" do
    it "preserves standard markdown through md→Telegram→md" do
      markdown = "**bold** and *italic*"
      telegram = converter.from_markdown(markdown)
      back = converter.to_markdown(telegram)
      expect(back).to eq(markdown)
    end

    it "normalizes escaped chars through Telegram→md→Telegram" do
      telegram_text = 'hello\. world\!'
      markdown = converter.to_markdown(telegram_text)
      expect(markdown).to eq("hello. world!")
      back = converter.from_markdown(markdown)
      expect(back).to eq(telegram_text)
    end
  end
end
