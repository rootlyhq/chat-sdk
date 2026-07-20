# frozen_string_literal: true

module ChatSDK
  module Linear
    class FormatConverter < ChatSDK::Format::Converter
      # Pass-through: Linear uses standard Markdown
    end
  end
end
