# frozen_string_literal: true

require "json"
require "openssl"
require "socket"
require "timeout"

module ChatSDK
  module GChat
    class TokenVerifier
      EXPECTED_ISSUER = "chat@system.gserviceaccount.com"
      CHAT_ISSUER_CERTS_URL = "https://www.googleapis.com/service_accounts/v1/metadata/x509/chat@system.gserviceaccount.com"
      WORKSPACE_ADD_ON_EMAIL_PATTERN = /\Aservice-\d+@gcp-sa-gsuiteaddons\.iam\.gserviceaccount\.com\z/

      def initialize(
        project_number = nil,
        endpoint_url: nil,
        pubsub_audience: nil,
        pubsub_service_account_email: nil,
        workspace_add_on_service_account_email: nil,
        disable_signature_verification: false
      )
        @project_number = project_number.to_s unless project_number.nil?
        @endpoint_url = endpoint_url
        @pubsub_audience = pubsub_audience
        @pubsub_service_account_email = pubsub_service_account_email
        @workspace_add_on_service_account_email = workspace_add_on_service_account_email
        @disable_signature_verification = disable_signature_verification
        @warned_unverified_direct = false
        @warned_unverified_pubsub = false
      end

      def verify!(token)
        verify_direct!(token)
      end

      def verify_request!(rack_request)
        rack_request.body.rewind
        body = rack_request.body.read
        rack_request.body.rewind

        payload = parse_request_body(body)
        if pubsub_push?(payload)
          verify_pubsub!(bearer_token(rack_request))
        else
          verify_direct!(bearer_token(rack_request))
        end
        true
      ensure
        rack_request.body.rewind
      end

      private

      def verify_direct!(token)
        unless @endpoint_url || @project_number
          return allow_unverified!(:direct) if @disable_signature_verification

          raise ChatSDK::SignatureVerificationError, "Direct Google Chat webhook verification is not configured"
        end

        raise ChatSDK::SignatureVerificationError, "Missing bearer token" if token.nil? || token.empty?

        failures = []
        if @endpoint_url
          begin
            payload = Google::Auth::IDTokens.verify_oidc(token, aud: @endpoint_url)
            return payload if endpoint_payload_trusted?(payload)

            failures << "Untrusted endpoint URL token identity"
          rescue Google::Auth::IDTokens::VerificationError,
            Google::Auth::IDTokens::KeySourceError,
            SocketError,
            Timeout::Error,
            IOError,
            SystemCallError,
            OpenSSL::OpenSSLError => e
            failures << e.message
          end
        end

        if @project_number
          begin
            return project_number_verifier.verify(token)
          rescue Google::Auth::IDTokens::VerificationError,
            Google::Auth::IDTokens::KeySourceError,
            SocketError,
            Timeout::Error,
            IOError,
            SystemCallError,
            OpenSSL::OpenSSLError => e
            failures << e.message
          end
        end

        message = failures.last ? ": #{failures.last}" : ""
        raise ChatSDK::SignatureVerificationError, "Google Chat webhook token verification failed#{message}"
      end

      def verify_pubsub!(token)
        unless @pubsub_audience
          return allow_unverified!(:pubsub) if @disable_signature_verification

          raise ChatSDK::SignatureVerificationError, "Google Chat Pub/Sub verification is not configured"
        end

        raise ChatSDK::SignatureVerificationError, "Missing bearer token" if token.nil? || token.empty?

        payload = Google::Auth::IDTokens.verify_oidc(token, aud: @pubsub_audience)
        unless pubsub_payload_trusted?(payload)
          raise ChatSDK::SignatureVerificationError, "Untrusted Google Chat Pub/Sub service account"
        end

        payload
      rescue Google::Auth::IDTokens::VerificationError,
        Google::Auth::IDTokens::KeySourceError,
        SocketError,
        Timeout::Error,
        IOError,
        SystemCallError,
        OpenSSL::OpenSSLError => e
        raise ChatSDK::SignatureVerificationError, "Google Pub/Sub ID token verification failed: #{e.message}"
      end

      def endpoint_payload_trusted?(payload)
        return false unless payload["email_verified"] == true

        email = payload["email"]
        return true if email == EXPECTED_ISSUER

        email.is_a?(String) &&
          WORKSPACE_ADD_ON_EMAIL_PATTERN.match?(email) &&
          email == @workspace_add_on_service_account_email
      end

      def pubsub_payload_trusted?(payload)
        payload["email_verified"] == true &&
          @pubsub_service_account_email &&
          payload["email"] == @pubsub_service_account_email
      end

      def project_number_verifier
        @project_number_verifier ||= Google::Auth::IDTokens::Verifier.new(
          key_source: Google::Auth::IDTokens::X509CertHttpKeySource.new(CHAT_ISSUER_CERTS_URL),
          aud: @project_number,
          iss: EXPECTED_ISSUER
        )
      end

      def allow_unverified!(transport)
        warning_ivar = :"@warned_unverified_#{transport}"
        return true if instance_variable_get(warning_ivar)

        ChatSDK::Log.warn("Google Chat #{transport} signature verification is disabled.")
        instance_variable_set(warning_ivar, true)
        true
      end

      def parse_request_body(body)
        JSON.parse(body)
      rescue JSON::ParserError
        nil
      end

      def pubsub_push?(payload)
        return false unless payload.is_a?(Hash)

        message = payload["message"]
        message.is_a?(Hash) && message.key?("data") && payload.key?("subscription")
      end

      def bearer_token(rack_request)
        authorization = rack_request.env["HTTP_AUTHORIZATION"].to_s
        match = /\ABearer\s+(.+)\z/i.match(authorization)
        match && match[1]
      end
    end
  end
end
