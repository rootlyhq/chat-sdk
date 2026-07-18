# frozen_string_literal: true

module ChatSDK
  module Teams
    class JwtVerifier
      OPENID_CONFIG_URL = "https://login.botframework.com/v1/.well-known/openidconfiguration"
      JWKS_CACHE_TTL = 3600 # 1 hour

      def initialize(app_id:)
        @app_id = app_id
        @jwks_keys = nil
        @jwks_fetched_at = nil
      end

      def verify!(token)
        raise ChatSDK::SignatureVerificationError, "Missing authorization token" if token.nil? || token.empty?

        jwks = fetch_jwks
        header = JWT.decode(token, nil, false).last
        kid = header["kid"]

        key = jwks.find { |k| k[:kid] == kid }
        raise ChatSDK::SignatureVerificationError, "Unknown signing key" unless key

        decoded = JWT.decode(
          token,
          key[:key],
          true,
          algorithm: header["alg"] || "RS256",
          aud: @app_id,
          verify_aud: true
        )
        decoded.first
      rescue JWT::DecodeError, JWT::VerificationError, JWT::ExpiredSignature, JWT::InvalidAudError => e
        raise ChatSDK::SignatureVerificationError, "JWT verification failed: #{e.message}"
      end

      private

      def fetch_jwks
        if @jwks_keys && @jwks_fetched_at && (Time.now - @jwks_fetched_at) < JWKS_CACHE_TTL
          return @jwks_keys
        end

        config_response = Faraday.get(OPENID_CONFIG_URL)
        config = JSON.parse(config_response.body)
        jwks_uri = config["jwks_uri"]

        jwks_response = Faraday.get(jwks_uri)
        jwks_data = JSON.parse(jwks_response.body)

        @jwks_keys = jwks_data["keys"].map do |key_data|
          next unless key_data["kty"] == "RSA"

          rsa_key = build_rsa_key(key_data)
          {kid: key_data["kid"], key: rsa_key}
        end.compact

        @jwks_fetched_at = Time.now
        @jwks_keys
      end

      def build_rsa_key(key_data)
        n = base64url_to_bn(key_data["n"])
        e = base64url_to_bn(key_data["e"])

        # Build RSA public key via DER encoding (compatible with OpenSSL 3.x)
        rsa_public_key = OpenSSL::ASN1::Sequence.new([
          OpenSSL::ASN1::Integer.new(n),
          OpenSSL::ASN1::Integer.new(e)
        ])

        der = OpenSSL::ASN1::Sequence.new([
          OpenSSL::ASN1::Sequence.new([
            OpenSSL::ASN1::ObjectId.new("rsaEncryption"),
            OpenSSL::ASN1::Null.new(nil)
          ]),
          OpenSSL::ASN1::BitString.new(rsa_public_key.to_der)
        ]).to_der

        OpenSSL::PKey::RSA.new(der)
      end

      def base64url_to_bn(str)
        decoded = Base64.urlsafe_decode64(str)
        OpenSSL::BN.new(decoded, 2)
      end
    end
  end
end
