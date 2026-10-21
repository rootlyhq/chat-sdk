# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::Slack::TokenEncryption do
  let(:key) { described_class.decode_key("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef") }

  describe ".encrypt and .decrypt" do
    it "round trips plaintext" do
      encrypted = described_class.encrypt("xoxb-test-token", key)

      expect(described_class.decrypt(encrypted, key)).to eq("xoxb-test-token")
      expect(encrypted.keys).to contain_exactly("iv", "data", "tag")
    end

    it "uses a random IV for each encryption" do
      first = described_class.encrypt("xoxb-test-token", key)
      second = described_class.encrypt("xoxb-test-token", key)

      expect(first["iv"]).not_to eq(second["iv"])
      expect(first["data"]).not_to eq(second["data"])
    end

    it "rejects a wrong key" do
      encrypted = described_class.encrypt("xoxb-test-token", key)
      wrong_key = described_class.decode_key("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")

      expect { described_class.decrypt(encrypted, wrong_key) }.to raise_error(OpenSSL::Cipher::CipherError)
    end

    it "rejects tampered ciphertext" do
      encrypted = described_class.encrypt("xoxb-test-token", key)
      encrypted["data"] = Base64.strict_encode64("tampered")

      expect { described_class.decrypt(encrypted, key) }.to raise_error(OpenSSL::Cipher::CipherError)
    end

    it "accepts symbol keys when decrypting" do
      encrypted = described_class.encrypt("xoxb-test-token", key).transform_keys(&:to_sym)

      expect(described_class.decrypt(encrypted, key)).to eq("xoxb-test-token")
    end

    it "decrypts the Node crypto interoperability fixture" do
      encrypted = {
        "iv" => "AAECAwQFBgcICQoL",
        "data" => "+WvifyuJTWz/5q96D8vXsi0=",
        "tag" => "3Qx8M2uVczExivJdh+UiaQ=="
      }
      fixture_key = described_class.decode_key("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")

      expect(described_class.decrypt(encrypted, fixture_key)).to eq("xoxb-node-fixture")
    end
  end

  describe ".decode_key" do
    it "decodes hex keys" do
      expect(described_class.decode_key("0123456789abcdef" * 4)).to eq(["0123456789abcdef" * 4].pack("H*"))
    end

    it "decodes base64 keys" do
      expect(described_class.decode_key(Base64.strict_encode64((0..31).to_a.pack("C*"))))
        .to eq((0..31).to_a.pack("C*"))
    end

    it "strips surrounding whitespace" do
      expect(described_class.decode_key("  #{Base64.strict_encode64((0..31).to_a.pack("C*"))}\n"))
        .to eq((0..31).to_a.pack("C*"))
    end

    it "rejects keys with the wrong decoded length" do
      expect { described_class.decode_key(Base64.strict_encode64("short")) }
        .to raise_error(
          ChatSDK::ConfigurationError,
          "Encryption key must decode to exactly 32 bytes (received 5). Use a 64-char hex string or 44-char base64 string."
        )
    end

    it "rejects an empty key" do
      expect { described_class.decode_key("") }
        .to raise_error(ChatSDK::ConfigurationError, /received 0/)
    end
  end

  describe ".encrypted?" do
    it "recognizes encrypted token hashes with string or symbol keys" do
      expect(described_class.encrypted?({"iv" => "iv", "data" => "data", "tag" => "tag"})).to be(true)
      expect(described_class.encrypted?({iv: "iv", data: "data", tag: "tag"})).to be(true)
    end

    it "rejects plaintext and malformed values" do
      expect(described_class.encrypted?("xoxb-plain")).to be(false)
      expect(described_class.encrypted?(nil)).to be(false)
      expect(described_class.encrypted?({"iv" => "iv", "data" => "data"})).to be(false)
      expect(described_class.encrypted?({"iv" => "iv", "data" => 1, "tag" => "tag"})).to be(false)
    end
  end
end
