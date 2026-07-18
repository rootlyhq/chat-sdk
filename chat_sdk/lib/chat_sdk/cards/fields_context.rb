# frozen_string_literal: true

module ChatSDK
  module Cards
    class FieldsContext
      attr_reader :nodes

      def initialize
        @nodes = []
      end

      def field(label, value)
        @nodes << Node.new(:field, attributes: {label: label, value: value})
      end
    end
  end
end
