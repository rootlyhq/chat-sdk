module ChatSDK
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class NotSupportedError < Error
    attr_reader :capability, :adapter_name
    def initialize(capability, adapter_name)
      @capability = capability
      @adapter_name = adapter_name
      super("#{adapter_name} adapter does not support #{capability}")
    end
  end
  class LockConflictError < Error; end
  class SignatureVerificationError < Error; end
  class PlatformError < Error
    attr_reader :status, :body, :adapter_name
    def initialize(message, status: nil, body: nil, adapter_name: nil)
      @status = status
      @body = body
      @adapter_name = adapter_name
      super(message)
    end
  end
  class RateLimitedError < PlatformError
    attr_reader :retry_after
    def initialize(message, retry_after: nil, **kwargs)
      @retry_after = retry_after
      super(message, **kwargs)
    end
  end
  class DuplicateEventError < Error; end
end
