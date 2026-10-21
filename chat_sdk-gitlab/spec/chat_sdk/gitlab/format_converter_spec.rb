# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::GitLab::FormatConverter do
  subject(:converter) { described_class.new }

  it "preserves GitLab-flavored Markdown references and mentions" do
    markdown = "Fixes #123 and mentions @alice; see !42."

    expect(converter.from_markdown(markdown)).to eq(markdown)
    expect(converter.to_markdown(markdown)).to eq(markdown)
  end
end
