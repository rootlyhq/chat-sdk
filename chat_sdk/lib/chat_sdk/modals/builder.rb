# frozen_string_literal: true

module ChatSDK
  module Modals
    class Builder
      def initialize(title:, submit_label: nil, callback_id: nil, &block)
        @title = title
        @submit_label = submit_label
        @callback_id = callback_id
        @children = []
        instance_eval(&block) if block
      end

      def build
        attrs = {title: @title}
        attrs[:submit_label] = @submit_label if @submit_label
        attrs[:callback_id] = @callback_id if @callback_id
        ChatSDK::Cards::Node.new(:modal, attributes: attrs, children: @children)
      end

      def text_input(id:, label:, placeholder: nil, multiline: false, optional: false)
        attrs = {id: id, label: label, input_type: :text, multiline: multiline, optional: optional}
        attrs[:placeholder] = placeholder if placeholder
        @children << ChatSDK::Cards::Node.new(:input, attributes: attrs)
      end

      def select_input(id:, label:, placeholder: nil, optional: false, &block)
        ctx = ChatSDK::Cards::SelectContext.new
        ctx.instance_eval(&block)
        attrs = {id: id, label: label, input_type: :select, optional: optional}
        attrs[:placeholder] = placeholder if placeholder
        @children << ChatSDK::Cards::Node.new(:input, attributes: attrs, children: ctx.nodes)
      end

      def static_text(content)
        @children << ChatSDK::Cards::Node.new(:text, attributes: {content: content})
      end
    end
  end
end
