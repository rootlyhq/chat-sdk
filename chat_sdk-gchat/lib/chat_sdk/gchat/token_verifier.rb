# frozen_string_literal: true

module ChatSDK
  module GChat
    class TokenVerifier
      EXPECTED_ISSUER = "chat@system.gserviceaccount.com"

      def initialize(project_number)
        @project_number = project_number.to_s
      end

      def verify!(token)
        raise ChatSDK::SignatureVerificationError, "Missing bearer token" if token.nil? || token.empty?

        payload = Google::Auth::IDTokens.verify_oidc(
          token,
          aud: @project_number
        )

        issuer = payload["iss"] || payload["email"]
        unless issuer == EXPECTED_ISSUER
          raise ChatSDK::SignatureVerificationError,
            "Unexpected issuer: #{issuer} (expected #{EXPECTED_ISSUER})"
        end

        payload
      rescue Google::Auth::IDTokens::VerificationError => e
        raise ChatSDK::SignatureVerificationError, "Google ID token verification failed: #{e.message}"
      end
    end
  end
end
