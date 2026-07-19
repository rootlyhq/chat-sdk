# frozen_string_literal: true

require "openssl"
require "rack/utils"

module ChatSDK
  module Adapter
    module MetaVerification
      def verify_meta_signature!(rack_request, secret:, platform_name:)
        signature = rack_request.get_header("HTTP_X_HUB_SIGNATURE_256")

        unless signature
          raise ChatSDK::SignatureVerificationError, "Missing #{platform_name} signature header"
        end

        body = rack_request.body.read
        rack_request.body.rewind

        expected = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, body)}"

        unless Rack::Utils.secure_compare(signature, expected)
          raise ChatSDK::SignatureVerificationError, "Invalid #{platform_name} signature"
        end

        true
      end

      def meta_ack_response(rack_request, verify_token:)
        return nil unless rack_request.get?

        params = rack_request.params
        mode = params["hub.mode"]
        token = params["hub.verify_token"]
        challenge = params["hub.challenge"]

        if mode == "subscribe" && token == verify_token
          [200, {}, [challenge.to_s]]
        end
      end
    end
  end
end
