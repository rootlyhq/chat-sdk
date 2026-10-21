# frozen_string_literal: true

module ChatSDK
  module Cards
    class ActionsContext
      attr_reader :nodes

      def initialize
        @nodes = []
      end

      def button(text, id:, style: nil, value: nil, tooltip: nil, visible_to: nil, disabled: nil)
        attrs = {text: text, id: id}
        attrs[:style] = style if style
        attrs[:value] = value if value
        attrs[:tooltip] = tooltip if tooltip
        attrs[:visible_to] = visible_to if visible_to
        attrs[:disabled] = disabled unless disabled.nil?
        @nodes << Node.new(:button, attributes: attrs)
      end

      def link_button(text, url:, id: nil, style: nil, tooltip: nil, visible_to: nil)
        attrs = {text: text, url: url}
        attrs[:id] = id if id
        attrs[:style] = style if style
        attrs[:tooltip] = tooltip if tooltip
        attrs[:visible_to] = visible_to if visible_to
        @nodes << Node.new(:link_button, attributes: attrs)
      end

      def select(id:, placeholder: nil, label: nil, initial_option: nil, optional: nil, dispatch_action: nil, &block)
        ctx = SelectContext.new
        ctx.instance_eval(&block) if block
        raise ArgumentError, "Select requires at least one option" if ctx.nodes.empty?

        attrs = {id: id}
        attrs[:placeholder] = placeholder if placeholder
        attrs[:label] = label unless label.nil?
        attrs[:initial_option] = initial_option unless initial_option.nil?
        attrs[:optional] = optional unless optional.nil?
        attrs[:dispatch_action] = dispatch_action unless dispatch_action.nil?
        @nodes << Node.new(:select, attributes: attrs, children: ctx.nodes)
      end

      def radio_select(id:, label:, initial_option: nil, optional: nil, dispatch_action: nil, &block)
        ctx = SelectContext.new
        ctx.instance_eval(&block) if block
        raise ArgumentError, "RadioSelect requires at least one option" if ctx.nodes.empty?

        attrs = {id: id, label: label}
        attrs[:initial_option] = initial_option unless initial_option.nil?
        attrs[:optional] = optional unless optional.nil?
        attrs[:dispatch_action] = dispatch_action unless dispatch_action.nil?
        @nodes << Node.new(:radio_select, attributes: attrs, children: ctx.nodes)
      end
    end
  end
end
