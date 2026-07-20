# frozen_string_literal: true

module ChatSDK
  module Mattermost
    class FormatConverter < ChatSDK::Format::Converter
      # Pass-through: Mattermost uses standard Markdown
    end
  end
end
