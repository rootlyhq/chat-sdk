# frozen_string_literal: true

module ChatSDK
  module Cards
    class Node
      attr_reader :type, :attributes, :children

      def initialize(type, attributes: {}, children: [])
        @type = type
        @attributes = attributes
        @children = children.freeze
      end

      def fallback_text
        collect_text.join("\n").strip
      end

      def ==(other)
        other.is_a?(Node) && type == other.type &&
          attributes == other.attributes && children == other.children
      end

      private

      def collect_text(nodes = [self])
        nodes.flat_map do |node|
          case node.type
          when :text
            [node.attributes[:content]]
          when :field
            ["#{node.attributes[:label]}: #{node.attributes[:value]}"]
          when :button, :link_button
            [node.attributes[:text]]
          when :table
            table_text(node)
          when :chart
            chart_text(node)
          else
            collect_text(node.children)
          end
        end
      end

      def table_text(node)
        headers = Array(node.attributes[:headers]).map(&:to_s)
        rows = Array(node.attributes[:rows]).map { |row| Array(row).map(&:to_s) }
        lines = []
        lines << node.attributes[:caption].to_s if node.attributes[:caption]
        lines << headers.join(" | ") unless headers.empty?
        lines.concat(rows.map { |row| row.join(" | ") })
        lines
      end

      def chart_text(node)
        lines = [node.attributes[:title].to_s]
        if node.attributes[:chart_type].to_sym == :pie
          lines.concat(Array(node.attributes[:segments]).map do |segment|
            "#{value_for(segment, :label)}: #{value_for(segment, :value)}"
          end)
        else
          Array(node.attributes[:series]).each do |series|
            data = value_for(series, :data) || []
            points = data.map { |point| "#{value_for(point, :label)}=#{value_for(point, :value)}" }
            lines << "#{value_for(series, :name)}: #{points.join(", ")}"
          end
        end
        lines
      end

      def value_for(hash, key)
        hash[key] || hash[key.to_s]
      end
    end
  end
end
