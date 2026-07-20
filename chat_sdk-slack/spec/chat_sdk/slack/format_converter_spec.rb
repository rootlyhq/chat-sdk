# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::Slack::FormatConverter do
  subject(:converter) { described_class.new }

  # ────────────────────────────────────────────────────────────────────────────
  # to_markdown — Slack mrkdwn → standard Markdown
  # ────────────────────────────────────────────────────────────────────────────

  describe "#to_markdown" do
    it "converts bold *text* to **text**" do
      expect(converter.to_markdown("*bold*")).to eq("**bold**")
    end

    it "converts italic _text_ to *text*" do
      expect(converter.to_markdown("_italic_")).to eq("*italic*")
    end

    it "converts strikethrough ~text~ to ~~text~~" do
      expect(converter.to_markdown("~strike~")).to eq("~~strike~~")
    end

    it "leaves inline code unchanged" do
      expect(converter.to_markdown("`code`")).to eq("`code`")
    end

    it "leaves fenced code blocks unchanged" do
      input = "```\nsome code\n```"
      expect(converter.to_markdown(input)).to eq(input)
    end

    it "converts links with labels" do
      expect(converter.to_markdown("<https://example.com|Example>")).to eq("[Example](https://example.com)")
    end

    it "converts bare links" do
      expect(converter.to_markdown("<https://example.com>")).to eq("https://example.com")
    end

    it "converts user mentions" do
      expect(converter.to_markdown("<@U123ABC>")).to eq("@U123ABC")
    end

    it "converts channel mentions with label" do
      expect(converter.to_markdown("<#C123|general>")).to eq("#general")
    end

    it "converts channel mentions without label" do
      expect(converter.to_markdown("<#C123>")).to eq("#C123")
    end

    it "converts <!everyone> to @everyone" do
      expect(converter.to_markdown("<!everyone>")).to eq("@everyone")
    end

    it "converts <!here> to @here" do
      expect(converter.to_markdown("<!here>")).to eq("@here")
    end

    it "converts <!channel> to @channel" do
      expect(converter.to_markdown("<!channel>")).to eq("@channel")
    end

    it "converts &gt; to >" do
      expect(converter.to_markdown("&gt;")).to eq(">")
    end

    it "converts &lt; to <" do
      expect(converter.to_markdown("&lt;")).to eq("<")
    end

    it "converts &amp; to &" do
      expect(converter.to_markdown("&amp;")).to eq("&")
    end

    it "converts blockquote &gt; prefix" do
      expect(converter.to_markdown("&gt; quoted text")).to eq("> quoted text")
    end

    it "handles nested bold and italic" do
      expect(converter.to_markdown("*bold _italic_*")).to eq("**bold *italic***")
    end

    it "leaves plain text unchanged" do
      expect(converter.to_markdown("hello world")).to eq("hello world")
    end

    it "returns empty string for empty input" do
      expect(converter.to_markdown("")).to eq("")
    end

    it "returns empty string for nil input" do
      expect(converter.to_markdown(nil)).to eq("")
    end

    it "converts mixed formatting with link" do
      input = "Hello *world* check <https://example.com|this>"
      expected = "Hello **world** check [this](https://example.com)"
      expect(converter.to_markdown(input)).to eq(expected)
    end

    it "does not convert formatting inside fenced code blocks" do
      input = "before ```\n*not bold*\n``` after"
      result = converter.to_markdown(input)
      expect(result).to include("*not bold*")
      expect(result).not_to include("**not bold**")
    end

    it "does not convert formatting inside inline code" do
      input = "before `*not bold*` after"
      result = converter.to_markdown(input)
      expect(result).to include("`*not bold*`")
    end

    it "handles links with parentheses in URL" do
      input = "<https://example.com/path_(thing)|link>"
      expect(converter.to_markdown(input)).to eq("[link](https://example.com/path_(thing))")
    end

    it "converts multiple user mentions" do
      expect(converter.to_markdown("<@U1> and <@U2>")).to eq("@U1 and @U2")
    end

    it "converts bold text mid-sentence" do
      expect(converter.to_markdown("this is *important* stuff")).to eq("this is **important** stuff")
    end

    it "converts multiple bold words" do
      expect(converter.to_markdown("*one* and *two*")).to eq("**one** and **two**")
    end

    it "converts multiple italic words" do
      expect(converter.to_markdown("_one_ and _two_")).to eq("*one* and *two*")
    end

    it "handles multiline text with formatting" do
      input = "*bold line*\n_italic line_"
      expected = "**bold line**\n*italic line*"
      expect(converter.to_markdown(input)).to eq(expected)
    end

    it "handles link followed by bold" do
      input = "<https://example.com|click> and *bold*"
      expected = "[click](https://example.com) and **bold**"
      expect(converter.to_markdown(input)).to eq(expected)
    end

    it "handles multiple HTML entities in one string" do
      expect(converter.to_markdown("a &amp; b &lt; c &gt; d")).to eq("a & b < c > d")
    end
  end

  # ────────────────────────────────────────────────────────────────────────────
  # from_markdown — standard Markdown → Slack mrkdwn
  # ────────────────────────────────────────────────────────────────────────────

  describe "#from_markdown" do
    it "converts **bold** to *bold*" do
      expect(converter.from_markdown("**bold**")).to eq("*bold*")
    end

    it "converts *italic* to _italic_" do
      expect(converter.from_markdown("*italic*")).to eq("_italic_")
    end

    it "converts ~~strike~~ to ~strike~" do
      expect(converter.from_markdown("~~strike~~")).to eq("~strike~")
    end

    it "converts markdown links to Slack format" do
      expect(converter.from_markdown("[Example](https://example.com)")).to eq("<https://example.com|Example>")
    end

    it "leaves inline code unchanged" do
      expect(converter.from_markdown("`code`")).to eq("`code`")
    end

    it "leaves fenced code blocks unchanged" do
      input = "```\ncode\n```"
      expect(converter.from_markdown(input)).to eq(input)
    end

    it "does not convert formatting inside fenced code blocks" do
      input = "text ```\n**not bold**\n``` more"
      result = converter.from_markdown(input)
      expect(result).to include("**not bold**")
    end

    it "does not convert formatting inside inline code" do
      input = "text `**not bold**` more"
      result = converter.from_markdown(input)
      expect(result).to include("`**not bold**`")
    end

    it "leaves plain text unchanged" do
      expect(converter.from_markdown("hello world")).to eq("hello world")
    end

    it "returns empty string for empty input" do
      expect(converter.from_markdown("")).to eq("")
    end

    it "returns empty string for nil input" do
      expect(converter.from_markdown(nil)).to eq("")
    end

    it "converts blockquote > to &gt;" do
      expect(converter.from_markdown("> quoted")).to eq("&gt; quoted")
    end

    it "converts multiple bold segments" do
      expect(converter.from_markdown("**one** and **two**")).to eq("*one* and *two*")
    end

    it "converts mixed bold and italic" do
      expect(converter.from_markdown("**bold** and *italic*")).to eq("*bold* and _italic_")
    end

    it "converts links with surrounding text" do
      input = "Visit [here](https://example.com) now"
      expected = "Visit <https://example.com|here> now"
      expect(converter.from_markdown(input)).to eq(expected)
    end

    it "handles multiline with blockquotes" do
      input = "> line one\n> line two"
      expected = "&gt; line one\n&gt; line two"
      expect(converter.from_markdown(input)).to eq(expected)
    end
  end

  # ────────────────────────────────────────────────────────────────────────────
  # Round-trip tests — verify conversions are reversible
  # ────────────────────────────────────────────────────────────────────────────

  describe "round-trip: Slack -> Markdown -> Slack" do
    it "preserves bold" do
      slack = "*bold*"
      expect(converter.from_markdown(converter.to_markdown(slack))).to eq(slack)
    end

    it "preserves italic" do
      slack = "_italic_"
      expect(converter.from_markdown(converter.to_markdown(slack))).to eq(slack)
    end

    it "preserves links with labels" do
      slack = "<https://example.com|Example>"
      expect(converter.from_markdown(converter.to_markdown(slack))).to eq(slack)
    end

    it "preserves inline code" do
      slack = "`code here`"
      expect(converter.from_markdown(converter.to_markdown(slack))).to eq(slack)
    end

    it "preserves fenced code blocks" do
      slack = "```\ncode block\n```"
      expect(converter.from_markdown(converter.to_markdown(slack))).to eq(slack)
    end

    it "preserves strikethrough" do
      slack = "~strike~"
      expect(converter.from_markdown(converter.to_markdown(slack))).to eq(slack)
    end
  end

  describe "round-trip: Markdown -> Slack -> Markdown" do
    it "preserves bold" do
      md = "**bold**"
      expect(converter.to_markdown(converter.from_markdown(md))).to eq(md)
    end

    it "preserves italic" do
      md = "*italic*"
      expect(converter.to_markdown(converter.from_markdown(md))).to eq(md)
    end

    it "preserves links" do
      md = "[Example](https://example.com)"
      expect(converter.to_markdown(converter.from_markdown(md))).to eq(md)
    end

    it "preserves inline code" do
      md = "`code`"
      expect(converter.to_markdown(converter.from_markdown(md))).to eq(md)
    end

    it "preserves fenced code blocks" do
      md = "```\ncode\n```"
      expect(converter.to_markdown(converter.from_markdown(md))).to eq(md)
    end

    it "preserves strikethrough" do
      md = "~~strike~~"
      expect(converter.to_markdown(converter.from_markdown(md))).to eq(md)
    end
  end

  # ────────────────────────────────────────────────────────────────────────────
  # Inherited base class methods
  # ────────────────────────────────────────────────────────────────────────────

  describe "#parse" do
    it "parses markdown using commonmarker" do
      node = converter.parse("# Title")
      expect(node).not_to be_nil
    end
  end

  describe "#render_html" do
    it "renders HTML from a parsed node" do
      node = converter.parse("**bold**")
      expect(converter.render_html(node).strip).to eq("<p><strong>bold</strong></p>")
    end
  end
end
