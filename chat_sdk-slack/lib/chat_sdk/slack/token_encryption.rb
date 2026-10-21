# frozen_string_literal: true

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
            trimmed.unpack1("m0")
          rescue ArgumentError
            trimmed.unpack1("m")
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
          "iv" => [iv].pack("m0"),
          "data" => [encrypted].pack("m0"),
          "tag" => [cipher.auth_tag(TAG_LENGTH)].pack("m0")
        }
      end

      def decrypt(encrypted, key)
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key = key
        iv = field(encrypted, "iv").unpack1("m0")
        tag = field(encrypted, "tag").unpack1("m0")
        raise ArgumentError, "Invalid AES-256-GCM token fields" unless iv.bytesize == IV_LENGTH && tag.bytesize == TAG_LENGTH

        cipher.iv = iv
        cipher.auth_tag = tag
        (cipher.update(field(encrypted, "data").unpack1("m0")) + cipher.final).force_encoding(Encoding::UTF_8)
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
