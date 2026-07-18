# frozen_string_literal: true

require_relative "../../spec_helper"
require "chat_sdk/testing"

def redis_url
  ENV["REDIS_URL"] || "redis://localhost:6379"
end

def redis_available?
  client = RedisClient.config(url: redis_url).new_client
  client.call("PING") == "PONG"
rescue StandardError
  false
end

RSpec.describe ChatSDK::State::Redis, if: redis_available? do
  subject { described_class.new(url: redis_url) }

  before { subject.clear }

  ChatSDK::Testing::StateContract # trigger autoload
  it_behaves_like "a chat_sdk state adapter"

  describe "Lua lock release" do
    it "only releases if owner matches" do
      subject.acquire_lock("l1", owner: "a", ttl: 10)
      expect(subject.release_lock("l1", owner: "b")).to be false
      expect(subject.release_lock("l1", owner: "a")).to be true
    end
  end

  describe "TTL" do
    it "expires keys" do
      subject.set("k1", "v1", ttl: 0.1)
      sleep 0.15
      expect(subject.get("k1")).to be_nil
    end

    it "expires locks" do
      subject.acquire_lock("l1", owner: "a", ttl: 0.1)
      sleep 0.15
      expect(subject.acquire_lock("l1", owner: "b", ttl: 10)).to be true
    end
  end

  describe "#clear" do
    it "removes all chat_sdk keys" do
      subject.subscribe("t1")
      subject.set("k1", "v1")
      subject.clear
      expect(subject.subscribed?("t1")).to be false
      expect(subject.get("k1")).to be_nil
    end
  end
end
