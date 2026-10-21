# frozen_string_literal: true

module ChatSDK
  module Modals
    class Builder
      def initialize(title:, submit_label: nil, callback_id: nil, close_label: nil, &block)
        @title = title
        @submit_label = submit_label
        @callback_id = callback_id
        @close_label = close_label
        @children = []
        instance_eval(&block) if block
      end

      def build
        attrs = {title: @title}
        attrs[:submit_label] = @submit_label if @submit_label
        attrs[:callback_id] = @callback_id if @callback_id
        attrs[:close_label] = @close_label if @close_label
        ChatSDK::Cards::Node.new(:modal, attributes: attrs, children: @children)
      end

      def text_input(id:, label:, placeholder: nil, multiline: false, optional: false, initial_value: nil, max_length: nil)
        attrs = {id: id, label: label, input_type: :text, multiline: multiline, optional: optional}
        attrs[:placeholder] = placeholder if placeholder
        attrs[:initial_value] = initial_value unless initial_value.nil?
        attrs[:max_length] = max_length unless max_length.nil?
        @children << ChatSDK::Cards::Node.new(:input, attributes: attrs)
      end

      def select_input(id:, label:, placeholder: nil, optional: false, initial_option: nil, dispatch_action: nil, &block)
        ctx = ChatSDK::Cards::SelectContext.new
        ctx.instance_eval(&block) if block
        raise ArgumentError, "Select requires at least one option" if ctx.nodes.empty?

        attrs = {id: id, label: label, input_type: :select, optional: optional}
        attrs[:placeholder] = placeholder if placeholder
        attrs[:initial_option] = initial_option unless initial_option.nil?
        attrs[:dispatch_action] = dispatch_action unless dispatch_action.nil?
        @children << ChatSDK::Cards::Node.new(:input, attributes: attrs, children: ctx.nodes)
      end

      def radio_select_input(id:, label:, initial_option: nil, optional: nil, dispatch_action: nil, &block)
        ctx = ChatSDK::Cards::SelectContext.new
        ctx.instance_eval(&block) if block
        raise ArgumentError, "RadioSelect requires at least one option" if ctx.nodes.empty?

        attrs = {id: id, label: label, input_type: :radio_select}
        attrs[:initial_option] = initial_option unless initial_option.nil?
        attrs[:optional] = optional unless optional.nil?
        attrs[:dispatch_action] = dispatch_action unless dispatch_action.nil?
        @children << ChatSDK::Cards::Node.new(:input, attributes: attrs, children: ctx.nodes)
      end

      def external_select_input(id:, label:, placeholder: nil, min_query_length: nil, initial_option: nil, optional: nil)
        attrs = {id: id, label: label, input_type: :external_select}
        attrs[:placeholder] = placeholder if placeholder
        attrs[:min_query_length] = min_query_length unless min_query_length.nil?
        attrs[:initial_option] = initial_option unless initial_option.nil?
        attrs[:optional] = optional unless optional.nil?
        @children << ChatSDK::Cards::Node.new(:input, attributes: attrs)
      end

      def fields(&block)
        ctx = ChatSDK::Cards::FieldsContext.new
        ctx.instance_eval(&block)
        @children << ChatSDK::Cards::Node.new(:fields, children: ctx.nodes)
      end

      def date_input(id:, label:, initial_value: nil, placeholder: nil, optional: false)
        attrs = {id: id, label: label, input_type: :date, optional: optional}
        attrs[:initial_value] = initial_value if initial_value
        attrs[:placeholder] = placeholder if placeholder
        @children << ChatSDK::Cards::Node.new(:input, attributes: attrs)
      end

      def number_input(id:, label:, min: nil, max: nil, initial_value: nil, placeholder: nil, decimal: false, optional: false)
        attrs = {id: id, label: label, input_type: :number, decimal: decimal, optional: optional}
        attrs[:min] = min unless min.nil?
        attrs[:max] = max unless max.nil?
        attrs[:initial_value] = initial_value unless initial_value.nil?
        attrs[:placeholder] = placeholder if placeholder
        @children << ChatSDK::Cards::Node.new(:input, attributes: attrs)
      end

      def static_text(content)
        @children << ChatSDK::Cards::Node.new(:text, attributes: {content: content})
      end
    end
  end
end
