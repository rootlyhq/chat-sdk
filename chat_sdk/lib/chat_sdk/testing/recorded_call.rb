module ChatSDK
  module Testing
    class RecordedCall
      attr_reader :method_name, :arguments

      def initialize(method_name, **arguments)
        @method_name = method_name
        @arguments = arguments
      end

      def [](key)
        @arguments[key]
      end

      def to_h
        { method: @method_name }.merge(@arguments)
      end
    end
  end
end
