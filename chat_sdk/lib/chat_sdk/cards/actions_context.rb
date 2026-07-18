# frozen_string_literal: true

module ChatSDK
  module Cards
    class ActionsContext
      attr_reader :nodes

      def initialize
        @nodes = []
      end

      def button(text, id:, style: nil, value: nil)
        attrs = {text: text, id: id}
        attrs[:style] = style if style
        attrs[:value] = value if value
        @nodes << Node.new(:button, attributes: attrs)
      end

      def link_button(text, url:)
        @nodes << Node.new(:link_button, attributes: {text: text, url: url})
      end

      def select(id:, placeholder: nil, &block)
        ctx = SelectContext.new
        ctx.instance_eval(&block)
        attrs = {id: id}
        attrs[:placeholder] = placeholder if placeholder
        @nodes << Node.new(:select, attributes: attrs, children: ctx.nodes)
      end
    end
  end
end
