module ChatSDK
  module Events
    class Base
      attr_reader :type, :platform, :adapter_name, :raw, :timestamp

      def initialize(type:, platform:, adapter_name:, raw: nil, timestamp: nil)
        @type = type
        @platform = platform
        @adapter_name = adapter_name
        @raw = raw
        @timestamp = timestamp || Time.now
      end
    end
  end
end
