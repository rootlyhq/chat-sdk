# frozen_string_literal: true

require "base64"
require "openssl"
require "securerandom"

module ChatSDK
  module Slack
    module TokenEncryption
      KEY_LENGTH = 32
      IV_LENGTH = 12
      TAG_LENGTH = 16
      HEX_KEY_PATTERN = /\A[0-9a-fA-F]{64}\z/

      module_function

      def decode_key(raw)
        trimmed = raw.to_s.strip
        decoded = if HEX_KEY_PATTERN.match?(trimmed)
          [trimmed].pack("H*")
        else
          begin
            Base64.strict_decode64(trimmed)
          rescue ArgumentError
            Base64.decode64(trimmed)
          end
        end
        return decoded if decoded.bytesize == KEY_LENGTH

        raise ChatSDK::ConfigurationError,
          "Encryption key must decode to exactly 32 bytes (received #{decoded.bytesize}). Use a 64-char hex string or 44-char base64 string."
      end

      def encrypt(plaintext, key)
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.encrypt
        iv = SecureRandom.random_bytes(IV_LENGTH)
        cipher.key = key
        cipher.iv = iv
        encrypted = cipher.update(plaintext) + cipher.final

        {
          "iv" => Base64.strict_encode64(iv),
          "data" => Base64.strict_encode64(encrypted),
          "tag" => Base64.strict_encode64(cipher.auth_tag(TAG_LENGTH))
        }
      end

      def decrypt(encrypted, key)
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key = key
        iv = Base64.strict_decode64(field(encrypted, "iv"))
        tag = Base64.strict_decode64(field(encrypted, "tag"))
        raise ArgumentError, "Invalid AES-256-GCM token fields" unless iv.bytesize == IV_LENGTH && tag.bytesize == TAG_LENGTH

        cipher.iv = iv
        cipher.auth_tag = tag
        cipher.update(Base64.strict_decode64(field(encrypted, "data"))) + cipher.final
      end

      def encrypted?(value)
        value.is_a?(Hash) &&
          field(value, "iv").is_a?(String) &&
          field(value, "data").is_a?(String) &&
          field(value, "tag").is_a?(String)
      end

      def field(hash, key)
        hash.key?(key) ? hash[key] : hash[key.to_sym]
      end
      private_class_method :field
    end
  end
end
