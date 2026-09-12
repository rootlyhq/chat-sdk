# frozen_string_literal: true

module ChatSDK
  module Cards
    class Builder
      def initialize(title: nil, subtitle: nil, width: nil, &block)
        @title = title
        @subtitle = subtitle
        @width = width
        @children = []
        instance_eval(&block) if block
      end

      def build
        attrs = {}
        attrs[:title] = @title if @title
        attrs[:subtitle] = @subtitle if @subtitle
        attrs[:width] = @width if @width
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

      def table(headers:, rows:, align: nil, caption: nil, page_size: nil)
        attrs = {headers: headers, rows: rows}
        attrs[:align] = align if align
        attrs[:caption] = caption if caption
        attrs[:page_size] = page_size if page_size
        @children << Node.new(:table, attributes: attrs)
      end

      def chart(title:, type:, segments: nil, categories: nil, series: nil, x_label: nil, y_label: nil)
        attrs = {title: title, chart_type: type}
        attrs[:segments] = segments if segments
        attrs[:categories] = categories if categories
        attrs[:series] = series if series
        attrs[:x_label] = x_label if x_label
        attrs[:y_label] = y_label if y_label
        @children << Node.new(:chart, attributes: attrs)
      end
    end
  end
end
