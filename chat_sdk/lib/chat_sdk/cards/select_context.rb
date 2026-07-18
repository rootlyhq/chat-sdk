# frozen_string_literal: true

module ChatSDK
  module Cards
    class SelectContext
      attr_reader :nodes

      def initialize
        @nodes = []
      end

      def option(text, value:, description: nil)
        attrs = {text: text, value: value}
        attrs[:description] = description if description
        @nodes << Node.new(:option, attributes: attrs)
      end
    end
  end
end
