# frozen_string_literal: true

module ChatSDK
  module Discord
    module Signature
      def self.verify!(verify_key, signature_hex, timestamp, body)
        signature = [signature_hex].pack("H*")
        message = "#{timestamp}#{body}"
        verify_key.verify(signature, message)
        true
      rescue Ed25519::VerifyError, ArgumentError
        raise ChatSDK::SignatureVerificationError, "Invalid Discord signature"
      end
    end
  end
end
