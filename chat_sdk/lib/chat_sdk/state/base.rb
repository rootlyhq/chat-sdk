# frozen_string_literal: true

module ChatSDK
  module State
    class Base
      def subscribe(thread_id)
        raise NotImplementedError
      end

      def unsubscribe(thread_id)
        raise NotImplementedError
      end

      def subscribed?(thread_id)
        raise NotImplementedError
      end

      def acquire_lock(key, owner:, ttl:)
        raise NotImplementedError
      end

      def release_lock(key, owner:)
        raise NotImplementedError
      end

      def force_lock(key, owner:, ttl:)
        raise NotImplementedError
      end

      def get(key)
        raise NotImplementedError
      end

      def set(key, value, ttl: nil)
        raise NotImplementedError
      end

      def delete(key)
        raise NotImplementedError
      end

      def set_if_absent(key, value, ttl: nil)
        raise NotImplementedError
      end
    end
  end
end
