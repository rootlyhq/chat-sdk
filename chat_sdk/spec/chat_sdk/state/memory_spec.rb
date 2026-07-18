# frozen_string_literal: true

require_relative "../../../../spec/spec_helper"

RSpec.describe ChatSDK::State::Memory do
  subject { described_class.new }

  it_behaves_like "a chat_sdk state adapter"

  describe "TTL expiration" do
    it "expires keys after TTL" do
      subject.set("k1", "v1", ttl: 0.01)
      sleep 0.02
      expect(subject.get("k1")).to be_nil
    end

    it "expires locks after TTL" do
      subject.acquire_lock("l1", owner: "a", ttl: 0.01)
      sleep 0.02
      expect(subject.acquire_lock("l1", owner: "b", ttl: 10)).to be true
    end
  end

  describe "#clear" do
    it "removes everything" do
      subject.subscribe("t1")
      subject.set("k1", "v1")
      subject.acquire_lock("l1", owner: "a", ttl: 10)
      subject.clear
      expect(subject.subscribed?("t1")).to be false
      expect(subject.get("k1")).to be_nil
      expect(subject.acquire_lock("l1", owner: "b", ttl: 10)).to be true
    end
  end
end
