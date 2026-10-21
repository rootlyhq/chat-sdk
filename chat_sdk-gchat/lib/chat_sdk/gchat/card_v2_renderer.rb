# frozen_string_literal: true

require "cgi"

module ChatSDK
  module GChat
    class CardV2Renderer
      def render(node)
        case node.type
        when :card then render_card(node)
        else {cards_v2: [{card: {sections: [{widgets: [render_widget(node)]}]}}]}
        end
      end

      private

      def render_card(node)
        header = build_header(node)
        sections = build_sections(node.children)

        card = {}
        card[:header] = header if header
        card[:sections] = sections unless sections.empty?

        {cards_v2: [{card: card}]}
      end

      def build_header(node)
        image_url = node.attributes[:image_url]
        has_image_url = image_url && !image_url.empty?
        return nil unless node.attributes[:title] || has_image_url

        header = {title: node.attributes[:title] || ""}
        header[:subtitle] = node.attributes[:subtitle] if node.attributes[:subtitle]
        if has_image_url
          header[:imageUrl] = image_url
          header[:imageType] = "SQUARE"
        end
        header
      end

      def build_sections(children)
        sections = []
        current_widgets = []

        children.each do |child|
          case child.type
          when :divider
            sections << {widgets: current_widgets} unless current_widgets.empty?
            current_widgets = []
            sections << {widgets: [{divider: {}}]}
          when :section
            sections << {widgets: current_widgets} unless current_widgets.empty?
            current_widgets = []
            section = {}
            section[:header] = child.attributes[:title] if child.attributes[:title]
            section[:widgets] = child.children.flat_map { |c| render_widgets(c) }.compact
            sections << section
          else
            render_widgets(child).each { |w| current_widgets << w }
          end
        end

        sections << {widgets: current_widgets} unless current_widgets.empty?
        sections
      end

      def render_widget(node)
        case node.type
        when :text then render_text(node)
        when :link then render_link(node)
        when :fields then render_fields(node)
        when :image then render_image(node)
        when :actions then render_actions(node)
        when :divider then {divider: {}}
        when :select then render_select(node)
        when :radio_select then render_radio_select(node)
        end
      end

      def render_widgets(node)
        case node.type
        when :actions then render_actions_as_widgets(node)
        else
          widget = render_widget(node)
          widget ? [widget] : []
        end
      end

      def render_text(node)
        text = node.attributes[:content]
        text = "*#{text}*" if node.attributes[:style] == :bold
        {textParagraph: {text: text}}
      end

      def render_link(node)
        url = CGI.escapeHTML(node.attributes[:url].to_s)
        label = CGI.escapeHTML(node.attributes[:label].to_s)
        {textParagraph: {text: %(<a href="#{url}">#{label}</a>)}}
      end

      def render_fields(node)
        {
          decoratedText: {
            topLabel: node.children.map { |f| f.attributes[:label] }.join(" | "),
            text: node.children.map { |f| f.attributes[:value] }.join(" | ")
          }
        }
      end

      def render_image(node)
        img = {imageUrl: node.attributes[:url]}
        img[:altText] = node.attributes[:alt] if node.attributes[:alt]
        {image: img}
      end

      def render_actions(node)
        widgets = render_actions_as_widgets(node)
        # For single-widget render path, return the first widget (buttonList or select)
        widgets.first
      end

      def render_actions_as_widgets(node)
        widgets = []
        buttons = []
        node.children.each do |child|
          if %i[select radio_select].include?(child.type)
            widgets << render_button_list(buttons) unless buttons.empty?
            buttons = []
            widget = if child.type == :radio_select
              render_radio_select(child)
            else
              render_select(child)
            end
            widgets << widget
          else
            btn = render_action_element(child)
            buttons << btn if btn
          end
        end
        widgets << render_button_list(buttons) unless buttons.empty?
        widgets
      end

      def render_button_list(buttons)
        {buttonList: {buttons: buttons}}
      end

      def render_action_element(node)
        case node.type
        when :button then render_button(node)
        when :link_button then render_link_button(node)
        when :select then nil # selects are rendered as their own widget
        end
      end

      def render_button(node)
        btn = {
          text: node.attributes[:text],
          onClick: {
            action: {
              actionMethodName: node.attributes[:id]
            }
          }
        }

        if node.attributes[:value]
          btn[:onClick][:action][:parameters] = [
            {key: "value", value: node.attributes[:value]}
          ]
        end

        if node.attributes[:style] == :primary
          btn[:color] = {red: 0.0, green: 0.53, blue: 0.87, alpha: 1.0}
        elsif node.attributes[:style] == :danger
          btn[:color] = {red: 0.87, green: 0.17, blue: 0.17, alpha: 1.0}
        end
        btn[:disabled] = true if node.attributes[:disabled]

        btn
      end

      def render_link_button(node)
        button = {
          text: node.attributes[:text],
          onClick: {
            openLink: {url: node.attributes[:url]}
          }
        }
        if node.attributes[:style] == :primary
          button[:color] = {red: 0.0, green: 0.53, blue: 0.87, alpha: 1.0}
        elsif node.attributes[:style] == :danger
          button[:color] = {red: 0.87, green: 0.17, blue: 0.17, alpha: 1.0}
        end
        button
      end

      def render_select(node)
        render_selection_input(node, type: "DROPDOWN")
      end

      def render_radio_select(node)
        render_selection_input(node, type: "RADIO_BUTTON")
      end

      def render_selection_input(node, type:)
        {
          selectionInput: {
            name: node.attributes[:id],
            label: node.attributes[:label] || node.attributes[:placeholder] || "Select",
            type: type,
            items: node.children.map { |option| render_select_option(option, node.attributes[:initial_option]) }
          }
        }
      end

      def render_select_option(node, initial_option)
        option = {
          text: node.attributes[:text],
          value: node.attributes[:value]
        }
        if initial_option.nil?
          option[:selected] = false
        elsif node.attributes[:value] == initial_option
          option[:selected] = true
        end
        option
      end
    end
  end
end
