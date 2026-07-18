module ChatSDK
  module Cards
    class Builder
      def initialize(title: nil, subtitle: nil, &block)
        @title = title
        @subtitle = subtitle
        @children = []
        instance_eval(&block) if block
      end

      def build
        attrs = {}
        attrs[:title] = @title if @title
        attrs[:subtitle] = @subtitle if @subtitle
        Node.new(:card, attributes: attrs, children: @children)
      end

      def text(content)
        @children << Node.new(:text, attributes: { content: content })
      end

      def divider
        @children << Node.new(:divider)
      end

      def image(url:, alt: nil)
        @children << Node.new(:image, attributes: { url: url, alt: alt })
      end

      def fields(&block)
        ctx = FieldsContext.new
        ctx.instance_eval(&block)
        @children << Node.new(:fields, children: ctx.nodes)
      end

      def section(title = nil, &block)
        ctx = Builder.new
        ctx.instance_eval(&block)
        attrs = title ? { title: title } : {}
        @children << Node.new(:section, attributes: attrs, children: ctx.build.children)
      end

      def actions(&block)
        ctx = ActionsContext.new
        ctx.instance_eval(&block)
        @children << Node.new(:actions, children: ctx.nodes)
      end
    end

    class FieldsContext
      attr_reader :nodes

      def initialize
        @nodes = []
      end

      def field(label, value)
        @nodes << Node.new(:field, attributes: { label: label, value: value })
      end
    end

    class ActionsContext
      attr_reader :nodes

      def initialize
        @nodes = []
      end

      def button(text, id:, style: nil, value: nil)
        attrs = { text: text, id: id }
        attrs[:style] = style if style
        attrs[:value] = value if value
        @nodes << Node.new(:button, attributes: attrs)
      end

      def link_button(text, url:)
        @nodes << Node.new(:link_button, attributes: { text: text, url: url })
      end

      def select(id:, placeholder: nil, &block)
        ctx = SelectContext.new
        ctx.instance_eval(&block)
        attrs = { id: id }
        attrs[:placeholder] = placeholder if placeholder
        @nodes << Node.new(:select, attributes: attrs, children: ctx.nodes)
      end
    end

    class SelectContext
      attr_reader :nodes

      def initialize
        @nodes = []
      end

      def option(text, value:, description: nil)
        attrs = { text: text, value: value }
        attrs[:description] = description if description
        @nodes << Node.new(:option, attributes: attrs)
      end
    end
  end
end
