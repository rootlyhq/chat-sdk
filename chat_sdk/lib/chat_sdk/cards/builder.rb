# frozen_string_literal: true

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
        @children << Node.new(:text, attributes: {content: content})
      end

      def divider
        @children << Node.new(:divider)
      end

      def image(url:, alt: nil)
        @children << Node.new(:image, attributes: {url: url, alt: alt})
      end

      def fields(&block)
        ctx = FieldsContext.new
        ctx.instance_eval(&block)
        @children << Node.new(:fields, children: ctx.nodes)
      end

      def section(title = nil, &block)
        ctx = Builder.new
        ctx.instance_eval(&block)
        attrs = title ? {title: title} : {}
        @children << Node.new(:section, attributes: attrs, children: ctx.build.children)
      end

      def actions(&block)
        ctx = ActionsContext.new
        ctx.instance_eval(&block)
        @children << Node.new(:actions, children: ctx.nodes)
      end
    end
  end
end
