module ChatSDK
  module Testing
    module StateContract
      RSpec.shared_examples "a chat_sdk state adapter" do
        describe "subscriptions" do
          it "subscribes and checks" do
            subject.subscribe("thread_1")
            expect(subject.subscribed?("thread_1")).to be true
          end

          it "unsubscribes" do
            subject.subscribe("thread_1")
            subject.unsubscribe("thread_1")
            expect(subject.subscribed?("thread_1")).to be false
          end

          it "returns false for unsubscribed threads" do
            expect(subject.subscribed?("nonexistent")).to be false
          end
        end

        describe "locks" do
          it "acquires a lock" do
            expect(subject.acquire_lock("key1", owner: "a", ttl: 10)).to be true
          end

          it "prevents double acquisition" do
            subject.acquire_lock("key1", owner: "a", ttl: 10)
            expect(subject.acquire_lock("key1", owner: "b", ttl: 10)).to be false
          end

          it "releases a lock by owner" do
            subject.acquire_lock("key1", owner: "a", ttl: 10)
            expect(subject.release_lock("key1", owner: "a")).to be true
            expect(subject.acquire_lock("key1", owner: "b", ttl: 10)).to be true
          end

          it "does not release lock with wrong owner" do
            subject.acquire_lock("key1", owner: "a", ttl: 10)
            expect(subject.release_lock("key1", owner: "b")).to be false
          end

          it "force acquires a lock" do
            subject.acquire_lock("key1", owner: "a", ttl: 10)
            expect(subject.force_lock("key1", owner: "b", ttl: 10)).to be true
          end
        end

        describe "key-value store" do
          it "gets and sets values" do
            subject.set("k1", { "count" => 1 })
            expect(subject.get("k1")).to eq({ "count" => 1 })
          end

          it "returns nil for missing keys" do
            expect(subject.get("missing")).to be_nil
          end

          it "deletes keys" do
            subject.set("k1", "v1")
            subject.delete("k1")
            expect(subject.get("k1")).to be_nil
          end

          it "set_if_absent succeeds when key absent" do
            expect(subject.set_if_absent("k1", "v1")).to be true
            expect(subject.get("k1")).to eq("v1")
          end

          it "set_if_absent fails when key present" do
            subject.set("k1", "v1")
            expect(subject.set_if_absent("k1", "v2")).to be false
            expect(subject.get("k1")).to eq("v1")
          end
        end
      end
    end
  end
end
