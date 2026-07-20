# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::Teams::FormatConverter do
  subject(:converter) { described_class.new }

  describe "#to_markdown" do
    context "inline formatting" do
      it "converts bold tags" do
        expect(converter.to_markdown("<b>bold</b>")).to eq("**bold**")
      end

      it "converts strong tags" do
        expect(converter.to_markdown("<strong>bold</strong>")).to eq("**bold**")
      end

      it "converts italic tags" do
        expect(converter.to_markdown("<i>italic</i>")).to eq("*italic*")
      end

      it "converts em tags" do
        expect(converter.to_markdown("<em>italic</em>")).to eq("*italic*")
      end

      it "converts strikethrough with s tag" do
        expect(converter.to_markdown("<s>strike</s>")).to eq("~~strike~~")
      end

      it "converts strikethrough with strike tag" do
        expect(converter.to_markdown("<strike>strike</strike>")).to eq("~~strike~~")
      end

      it "converts strikethrough with del tag" do
        expect(converter.to_markdown("<del>deleted</del>")).to eq("~~deleted~~")
      end
    end

    context "code" do
      it "converts inline code" do
        expect(converter.to_markdown("<code>code</code>")).to eq("`code`")
      end

      it "converts pre blocks to fenced code blocks" do
        expect(converter.to_markdown("<pre>code block</pre>")).to eq("```\ncode block\n```")
      end

      it "preserves content inside code spans" do
        expect(converter.to_markdown("<code><b>not bold</b></code>")).to eq("`<b>not bold</b>`")
      end

      it "preserves content inside pre blocks" do
        expect(converter.to_markdown("<pre><b>not bold</b></pre>")).to eq("```\n<b>not bold</b>\n```")
      end
    end

    context "links" do
      it "converts anchor tags to markdown links" do
        expect(converter.to_markdown('<a href="https://example.com">Example</a>')).to eq("[Example](https://example.com)")
      end

      it "handles links with extra attributes" do
        expect(converter.to_markdown('<a href="https://example.com" target="_blank">Link</a>')).to eq("[Link](https://example.com)")
      end
    end

    context "mentions" do
      it "converts at tags to @mentions" do
        expect(converter.to_markdown("<at>alice</at>")).to eq("@alice")
      end
    end

    context "line breaks" do
      it "converts br tag to newline" do
        expect(converter.to_markdown("line1<br>line2")).to eq("line1\nline2")
      end

      it "converts self-closing br tag to newline" do
        expect(converter.to_markdown("line1<br/>line2")).to eq("line1\nline2")
      end

      it "converts br with space to newline" do
        expect(converter.to_markdown("line1<br />line2")).to eq("line1\nline2")
      end
    end

    context "HTML entities" do
      it "decodes &amp;" do
        expect(converter.to_markdown("A &amp; B")).to eq("A & B")
      end

      it "decodes &lt;" do
        expect(converter.to_markdown("1 &lt; 2")).to eq("1 < 2")
      end

      it "decodes &gt;" do
        expect(converter.to_markdown("2 &gt; 1")).to eq("2 > 1")
      end

      it "decodes &quot;" do
        expect(converter.to_markdown("&quot;quoted&quot;")).to eq('"quoted"')
      end
    end

    context "nested formatting" do
      it "converts nested bold italic" do
        expect(converter.to_markdown("<b><i>bold italic</i></b>")).to eq("***bold italic***")
      end
    end

    context "lists" do
      it "converts unordered lists" do
        html = "<ul><li>one</li><li>two</li></ul>"
        expect(converter.to_markdown(html)).to eq("- one\n- two")
      end

      it "converts ordered lists" do
        html = "<ol><li>first</li><li>second</li></ol>"
        expect(converter.to_markdown(html)).to eq("1. first\n2. second")
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

      it "handles mixed HTML and text" do
        expect(converter.to_markdown("Hello <b>world</b>!")).to eq("Hello **world**!")
      end

      it "strips unknown HTML tags" do
        expect(converter.to_markdown("<div>content</div>")).to eq("content")
      end
    end
  end

  describe "#from_markdown" do
    context "inline formatting" do
      it "converts bold" do
        expect(converter.from_markdown("**bold**")).to eq("<b>bold</b>")
      end

      it "converts italic" do
        expect(converter.from_markdown("*italic*")).to eq("<i>italic</i>")
      end

      it "converts strikethrough" do
        expect(converter.from_markdown("~~strike~~")).to eq("<s>strike</s>")
      end
    end

    context "code" do
      it "converts inline code" do
        expect(converter.from_markdown("`code`")).to eq("<code>code</code>")
      end

      it "converts fenced code blocks" do
        expect(converter.from_markdown("```\nblock\n```")).to eq("<pre>block</pre>")
      end

      it "does not convert formatting inside inline code" do
        expect(converter.from_markdown("`**not bold**`")).to eq("<code>**not bold**</code>")
      end

      it "does not convert formatting inside code blocks" do
        expect(converter.from_markdown("```\n**not bold**\n```")).to eq("<pre>**not bold**</pre>")
      end
    end

    context "links" do
      it "converts markdown links to HTML" do
        expect(converter.from_markdown("[text](https://example.com)")).to eq('<a href="https://example.com">text</a>')
      end
    end

    context "newlines" do
      it "converts newlines to br tags" do
        expect(converter.from_markdown("line1\nline2")).to eq("line1<br>line2")
      end
    end

    context "edge cases" do
      it "returns empty string for nil" do
        expect(converter.from_markdown(nil)).to eq("")
      end

      it "returns empty string for empty string" do
        expect(converter.from_markdown("")).to eq("")
      end

      it "returns plain text unchanged" do
        expect(converter.from_markdown("Hello world")).to eq("Hello world")
      end
    end
  end

  describe "round-trip" do
    it "preserves meaning through Teams HTML→md→Teams HTML" do
      teams_html = "<b>bold</b> and <i>italic</i>"
      markdown = converter.to_markdown(teams_html)
      expect(markdown).to eq("**bold** and *italic*")
      html = converter.from_markdown(markdown)
      expect(html).to eq("<b>bold</b> and <i>italic</i>")
    end

    it "preserves meaning through md→Teams→md" do
      markdown = "**bold** and *italic*"
      html = converter.from_markdown(markdown)
      expect(html).to eq("<b>bold</b> and <i>italic</i>")
      result = converter.to_markdown(html)
      expect(result).to eq("**bold** and *italic*")
    end

    it "preserves code blocks through round-trip" do
      markdown = "```\ncode here\n```"
      html = converter.from_markdown(markdown)
      expect(html).to eq("<pre>code here</pre>")
      result = converter.to_markdown(html)
      expect(result).to eq("```\ncode here\n```")
    end
  end
end
