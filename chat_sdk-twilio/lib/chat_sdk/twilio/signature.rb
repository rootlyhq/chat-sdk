# frozen_string_literal: true

require "openssl"
require "base64"
require "rack/utils"

module ChatSDK
  module Twilio
    module Signature
      def self.verify!(auth_token, url, params, signature)
        data = url + params.sort.join
        digest = OpenSSL::HMAC.digest("SHA1", auth_token, data)
        expected = Base64.strict_encode64(digest)

        unless Rack::Utils.secure_compare(expected, signature)
          raise ChatSDK::SignatureVerificationError, "Invalid Twilio signature"
        end

        true
      end
    end
  end
end
