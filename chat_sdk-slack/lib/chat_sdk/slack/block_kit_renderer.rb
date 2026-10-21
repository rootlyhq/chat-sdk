# frozen_string_literal: true

module ChatSDK
  module Slack
    class BlockKitRenderer
      def render(node)
        case node.type
        when :card then render_card(node)
        else [render_node(node)]
        end
      end

      private

      def render_card(node)
        @used_native_table = false
        @chart_count = 0
        blocks = []
        if node.attributes[:title]
          blocks << {type: "header", text: {type: "plain_text", text: truncate_text(node.attributes[:title], 150)}}
        end
        if node.attributes[:subtitle]
          blocks << {type: "context", elements: [{type: "mrkdwn", text: truncate_mrkdwn(node.attributes[:subtitle], 3000)}]}
        end
        if node.attributes[:image_url] && !node.attributes[:image_url].empty?
          blocks << {
            type: "image",
            image_url: node.attributes[:image_url],
            alt_text: truncate_text(node.attributes[:title] || "Card image", 2000)
          }
        end
        blocks.concat(node.children.map { |child| render_node(child) }.compact)
        blocks
      end

      def render_node(node)
        case node.type
        when :text then render_text(node)
        when :link then render_link(node)
        when :divider then {type: "divider"}
        when :image then render_image(node)
        when :fields then render_fields(node)
        when :section then render_section(node)
        when :actions then render_actions(node)
        when :table then render_table(node)
        when :chart then render_chart(node)
        when :text_input then {type: "section", text: {type: "mrkdwn", text: truncate_mrkdwn(node.attributes[:label], 3000)}}
        end
      end

      def render_text(node)
        content = node.attributes[:content]
        content = "*#{truncate_mrkdwn(content, 2998)}*" if node.attributes[:style] == :bold
        return {type: "context", elements: [{type: "mrkdwn", text: truncate_mrkdwn(content, 3000)}]} if node.attributes[:style] == :muted

        {
          type: "section",
          text: {type: "mrkdwn", text: truncate_mrkdwn(content, 3000)}
        }
      end

      def render_link(node)
        url = node.attributes[:url]
        label_budget = [2997 - url.to_s.length, 0].max
        label = truncate_mrkdwn(node.attributes[:label], label_budget)
        {type: "section", text: {type: "mrkdwn", text: "<#{url}|#{label}>"}}
      end

      def render_image(node)
        block = {type: "image", image_url: node.attributes[:url]}
        block[:alt_text] = truncate_text(node.attributes[:alt] || " ", 2000)
        block
      end

      def render_fields(node)
        {
          type: "section",
          fields: node.children.map do |field|
            {type: "mrkdwn", text: truncate_mrkdwn("*#{field.attributes[:label]}*\n#{field.attributes[:value]}", 2000)}
          end
        }
      end

      def render_section(node)
        block = {type: "section"}
        text_children = node.children.select { |c| c.type == :text }
        if text_children.any?
          block[:text] = {type: "mrkdwn", text: truncate_mrkdwn(text_children.map { |t| t.attributes[:content] }.join("\n"), 3000)}
        end
        block
      end

      def render_actions(node)
        {
          type: "actions",
          elements: node.children.map { |child| render_action_element(child) }.compact
        }
      end

      def render_action_element(node)
        case node.type
        when :button then render_button(node)
        when :link_button then render_link_button(node)
        when :select then render_select(node)
        when :radio_select then render_radio_select(node)
        end
      end

      def render_button(node)
        btn = {
          type: "button",
          text: {type: "plain_text", text: truncate_text(node.attributes[:text], 75)},
          action_id: node.attributes[:id]
        }
        btn[:value] = node.attributes[:value] if node.attributes[:value]
        if node.attributes[:style] == :primary
          btn[:style] = "primary"
        elsif node.attributes[:style] == :danger
          btn[:style] = "danger"
        end
        btn[:visible_to_user_ids] = node.attributes[:visible_to] if node.attributes[:visible_to]&.any?
        btn
      end

      def render_link_button(node)
        button = {
          type: "button",
          text: {type: "plain_text", text: truncate_text(node.attributes[:text], 75)},
          url: node.attributes[:url],
          action_id: node.attributes[:id] || "link_#{node.attributes[:url].hash.abs}"
        }
        if node.attributes[:style] == :primary
          button[:style] = "primary"
        elsif node.attributes[:style] == :danger
          button[:style] = "danger"
        end
        button[:visible_to_user_ids] = node.attributes[:visible_to] if node.attributes[:visible_to]&.any?
        button
      end

      def render_select(node)
        sel = {
          type: "static_select",
          action_id: node.attributes[:id],
          options: node.children.map { |opt| render_option(opt) }
        }
        if node.attributes[:placeholder]
          sel[:placeholder] = {type: "plain_text", text: truncate_text(node.attributes[:placeholder], 150)}
        end
        if node.attributes[:initial_option] && !node.attributes[:initial_option].empty?
          initial_option = sel[:options].find { |option| option[:value] == node.attributes[:initial_option] }
          sel[:initial_option] = initial_option if initial_option
        end
        sel
      end

      def render_radio_select(node)
        options = node.children.first(10).map do |option|
          rendered = {
            text: {type: "mrkdwn", text: truncate_mrkdwn(option.attributes[:text], 75)},
            value: option.attributes[:value]
          }
          if option.attributes[:description]
            rendered[:description] = {type: "mrkdwn", text: truncate_mrkdwn(option.attributes[:description], 75)}
          end
          rendered
        end
        element = {type: "radio_buttons", action_id: node.attributes[:id], options: options}
        if node.attributes[:initial_option] && !node.attributes[:initial_option].empty?
          initial_option = options.find { |option| option[:value] == node.attributes[:initial_option] }
          element[:initial_option] = initial_option if initial_option
        end
        element
      end

      def render_option(node)
        opt = {
          text: {type: "plain_text", text: truncate_text(node.attributes[:text], 75)},
          value: node.attributes[:value]
        }
        if node.attributes[:description]
          opt[:description] = {type: "plain_text", text: truncate_text(node.attributes[:description], 75)}
        end
        opt
      end

      def render_table(node)
        headers = Array(node.attributes[:headers])
        rows = Array(node.attributes[:rows])
        char_count = (headers + rows.flatten).sum { |cell| cell.to_s.length }
        if @used_native_table || rows.length > 100 || headers.length > 20 || char_count > 10_000
          return fallback_block(ChatSDK::Cards::Renderer.new.render(node))
        end

        @used_native_table = true
        rendered_rows = [headers, *rows].map do |row|
          Array(row).map { |cell| {type: "raw_text", text: cell.to_s.empty? ? " " : cell.to_s} }
        end
        return {type: "table", rows: rendered_rows} if rows.empty?

        block = {
          type: "data_table",
          caption: node.attributes[:caption] || "Table",
          rows: rendered_rows
        }
        block[:page_size] = node.attributes[:page_size].to_i.clamp(1, 100) if node.attributes[:page_size]
        block
      end

      def render_chart(node)
        return fallback_block(node.fallback_text) if @chart_count >= 2

        block = chart_block(node)
        return fallback_block(node.fallback_text) unless block

        @chart_count += 1
        block
      end

      def chart_block(node)
        title = node.attributes[:title].to_s
        return if title.empty? || title.length > 50

        type = node.attributes[:chart_type].to_sym
        if type == :pie
          segments = Array(node.attributes[:segments])
          return unless segments.length.between?(1, 12) && segments.all? { |segment| valid_chart_label?(value_for(segment, :label)) && value_for(segment, :value).to_f.positive? }

          return {type: "data_visualization", title: title, chart: {type: "pie", segments: segments}}
        end

        categories = Array(node.attributes[:categories])
        series = Array(node.attributes[:series])
        return unless %i[bar area line].include?(type)
        return unless categories.length.between?(1, 20) && categories.all? { |category| valid_chart_label?(category) }
        return unless series.length.between?(1, 12) && series.all? { |item| valid_chart_label?(value_for(item, :name)) }

        axis = {categories: categories}
        axis[:x_label] = node.attributes[:x_label] if node.attributes[:x_label]
        axis[:y_label] = node.attributes[:y_label] if node.attributes[:y_label]
        {type: "data_visualization", title: title, chart: {type: type.to_s, series: series, axis_config: axis}}
      end

      def valid_chart_label?(label)
        label.to_s.length.between?(1, 20)
      end

      def value_for(hash, key)
        hash[key] || hash[key.to_s]
      end

      def fallback_block(text)
        {type: "section", text: {type: "mrkdwn", text: truncate_mrkdwn("```#{text}```", 3000)}}
      end

      def truncate_text(text, limit)
        text = text.to_s
        return text if text.length <= limit

        "#{text[0, limit - 1]}…"
      end

      def truncate_mrkdwn(text, limit)
        text = text.to_s
        return text if text.length <= limit

        prefix = clean_prefix(text[0, limit - 1])
        4.times do
          bold_close = prefix.count("*").odd? ? "*" : ""
          fence_close = open_fence?(prefix) ? "\n```" : ""
          available = limit - 1 - bold_close.length - fence_close.length
          next_prefix = clean_prefix(text[0, available])
          break if next_prefix == prefix

          prefix = next_prefix
        end

        bold_close = prefix.count("*").odd? ? "*" : ""
        fence_close = open_fence?(prefix) ? "\n```" : ""
        suffix = "#{bold_close}…#{fence_close}"
        prefix = clean_prefix(prefix[0, limit - suffix.length]) while prefix.length + suffix.length > limit
        "#{prefix}#{suffix}"
      end

      def clean_prefix(text)
        text
          .sub(/<(?:[@#!]|[a-z][a-z\d+.-]*(?::|$))[^>]*\z/i, "")
          .sub(/&(?:#?[a-z\d]*)?\z/i, "")
      end

      def open_fence?(text)
        text.scan("```").length.odd?
      end
    end
  end
end
