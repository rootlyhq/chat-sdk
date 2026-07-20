# frozen_string_literal: true

module ChatSDK
  module GChat
    class FormatConverter < ChatSDK::Format::Converter
      # Pass-through: Google Chat uses standard Markdown in text messages
    end
  end
end
