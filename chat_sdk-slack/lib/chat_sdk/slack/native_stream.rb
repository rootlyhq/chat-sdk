# frozen_string_literal: true

require "socket"
require "timeout"

module ChatSDK
  module Slack
    class NativeStream
      STREAM_EXPIRED_ERROR = "message_not_in_streaming_state"
      ROTATION_GRACE = 30
      MAYBE_APPLIED_ERRORS = %w[fatal_error internal_error request_timeout service_unavailable].freeze
      UNSUPPORTED_ERRORS = %w[feature_not_enabled method_deprecated unknown_method].freeze
      FENCE_PATTERN = /^ {0,3}(`{3,}|~{3,})(.*)$/
      TABLE_ROW_PATTERN = /^\|.*\|$/
      TABLE_SEPARATOR_PATTERN = /^\|[\s:]*-+[\s:]*(?:\|[\s:]*-+[\s:]*)*\|$/

      Segment = Struct.new(:streamer, :started_at, :flush_next_append, :reopen_fence, :table_header)

      attr_reader :adapter, :channel_id, :thread_id, :stream, :options, :max_age

      def initialize(adapter:, channel_id:, thread_id:, stream:, options:, max_age:)
        @adapter = adapter
        @channel_id = channel_id
        @thread_id = thread_id
        @stream = stream
        @options = options
        @max_age = max_age
        @segment = build_segment
        @rotations = 0
        @finalized_message_ids = []
        @accumulated = +""
        @last_appended = +""
        @last_flushed = +""
        @fallback_message = nil
        @fallback_sent = +""
        @last_fallback_edit_at = nil
        @native_rendered = false
        @mode = :native
        @structured_chunks_supported = true
        @structured_warning_sent = false
        @open_tasks = {}
        @current_plan = nil
      end

      def run
        stream.each do |chunk|
          case chunk
          when String
            append_text(chunk)
          when ChatSDK::Streaming::MarkdownTextChunk
            append_text(chunk.text)
          when ChatSDK::Streaming::TaskUpdateChunk, ChatSDK::Streaming::PlanUpdateChunk
            send_structured_chunk(chunk)
          end
        end

        flush_committed(force: true)
        return finish_fallback if @mode == :fallback

        stop_native_stream
      end

      private

      def build_segment
        Segment.new(
          streamer: ChatStreamer.new(
            adapter.client,
            channel: channel_id,
            thread_ts: thread_id,
            recipient_user_id: options[:recipient_user_id],
            recipient_team_id: options[:recipient_team_id],
            task_display_mode: options[:task_display_mode]
          ),
          started_at: nil,
          flush_next_append: false,
          reopen_fence: "",
          table_header: ""
        )
      end

      def append_text(text)
        return if text.empty?

        @accumulated << text
        flush_committed
      end

      def flush_committed(force: false)
        if @mode == :fallback
          flush_fallback(force: force)
          return
        end

        delta = @accumulated[@last_appended.length..] || ""
        return if delta.empty?

        send_delta(delta, at_block_boundary: false)
      rescue *stream_error_classes => error
        raise if @native_rendered

        switch_to_fallback(error)
        flush_fallback(force: force)
      end

      def send_structured_chunk(chunk)
        flush_committed
        return unless @mode == :native && @structured_chunks_supported

        send_delta("", at_block_boundary: true)
        begin
          @segment.streamer.append(chunks: [chunk])
          mark_segment_started
          @last_flushed = @last_appended.dup
          remember_structured_chunk(chunk)
        rescue *slack_error_classes => error
          disable_structured_chunks(chunk.type, error)
        end
      end

      def stop_native_stream
        stop_blocks = options[:stop_blocks]
        result = begin
          @segment.streamer.stop(blocks: stop_blocks)
        rescue *stream_error_classes => error
          if !@native_rendered
            switch_to_fallback(error)
            flush_fallback(force: true)
            return finish_fallback
          end

          raise unless stream_expired?(error)

          unconfirmed = @last_appended[@last_flushed.length..] || ""
          expired_ts = @segment.streamer.ts
          if unconfirmed.empty?
            raise error unless expired_ts

            return build_message(
              id: expired_ts,
              response: nil,
              message_ids: @finalized_message_ids + [expired_ts]
            )
          end

          start_next_segment(@last_flushed)
          @segment.streamer.stop(
            markdown_text: with_segment_prefix(unconfirmed),
            blocks: stop_blocks
          )
        end
        message_id = response_value(result, :ts) || @segment.streamer.ts
        build_message(
          id: message_id,
          response: result,
          message_ids: @finalized_message_ids + [message_id]
        )
      end

      def send_delta(delta, at_block_boundary:)
        text = if rotation_due?(at_block_boundary || delta.include?("\n\n"))
          rotate_segment(delta)
        else
          delta
        end

        unless text.empty?
          response = @segment.streamer.append(
            markdown_text: with_segment_prefix(text),
            **(@segment.flush_next_append ? {chunks: []} : {})
          )
          if response
            mark_segment_started
            @last_flushed = @accumulated.dup
          end
        end
        @last_appended = @accumulated.dup
      end

      def rotation_due?(at_block_boundary)
        return false unless @segment.started_at

        age = monotonic_now - @segment.started_at
        age >= max_age && (at_block_boundary || age >= max_age + ROTATION_GRACE)
      end

      def rotate_segment(delta)
        cut_at = segment_cut_index(delta)
        head = delta[0...cut_at]
        tail = delta[cut_at..] || ""
        sent = @last_appended + head
        fence = open_fence_in(sent)
        if fence && sent.end_with?("\n") && closes_fence?(fence, tail)
          head << tail
          sent << tail
          tail = ""
          fence = nil
        end
        closer = if fence
          prefix = sent.end_with?("\n") ? "" : "\n"
          "#{prefix}#{fence[:marker]}"
        else
          ""
        end
        final_text = (head.empty? ? "" : with_segment_prefix(head)) + closer
        age = @segment.started_at ? monotonic_now - @segment.started_at : 0
        closing_tasks = if @structured_chunks_supported && !@open_tasks.empty?
          @open_tasks.values.map { |task| task.with(status: "complete") }
        end

        begin
          begin
            response = @segment.streamer.stop(
              markdown_text: final_text.empty? ? nil : final_text,
              chunks: closing_tasks
            )
          rescue *slack_error_classes => error
            code = platform_error_code(error)
            raise if closing_tasks.nil? || code.nil? || code == STREAM_EXPIRED_ERROR || MAYBE_APPLIED_ERRORS.include?(code)

            response = @segment.streamer.stop
            disable_structured_chunks("task_update", error)
          end
          @last_flushed = sent
          ChatSDK::Log.debug("Slack: rotated stream segment #{response_value(response, :ts)} after #{age}s")
        rescue *stream_error_classes => error
          raise unless stream_expired?(error)

          ChatSDK::Log.warn("Slack: stream segment expired before rotation; continuing in a new message")
          tail = (@last_appended[@last_flushed.length..] || "") + delta
          sent = @last_flushed.dup
        end

        start_next_segment(sent)
        tail
      end

      def start_next_segment(sent)
        old_ts = @segment.streamer.ts
        @finalized_message_ids << old_ts if old_ts
        @segment = build_segment
        @segment.flush_next_append = true
        fence = open_fence_in(sent)
        @segment.reopen_fence = "#{fence[:opening]}\n" if fence
        @segment.table_header = table_continuation(sent) unless fence
        @rotations += 1

        replay = []
        replay << @current_plan if @current_plan
        replay.concat(@open_tasks.values)
        return if replay.empty? || !@structured_chunks_supported

        @segment.streamer.append(chunks: replay)
        mark_segment_started
      rescue *slack_error_classes => error
        disable_structured_chunks("replay", error)
      end

      def with_segment_prefix(text)
        first_line = text.split("\n", 2).first.to_s
        header = TABLE_ROW_PATTERN.match?(first_line.strip) ? @segment.table_header : ""
        prefixed = @segment.reopen_fence + header + text
        @segment.reopen_fence = ""
        @segment.table_header = ""
        prefixed
      end

      def remember_structured_chunk(chunk)
        case chunk
        when ChatSDK::Streaming::PlanUpdateChunk
          @current_plan = chunk
        when ChatSDK::Streaming::TaskUpdateChunk
          if %w[complete error].include?(chunk.status)
            @open_tasks.delete(chunk.id)
          else
            @open_tasks[chunk.id] = chunk
          end
        end
      end

      def disable_structured_chunks(chunk_type, error)
        @structured_chunks_supported = false
        return if @structured_warning_sent

        @structured_warning_sent = true
        ChatSDK::Log.warn(
          "Structured Slack streaming chunks are unavailable; continuing with text only. " \
          "The Slack app requires the assistant:write scope (#{chunk_type}: #{error.message})"
        )
      end

      def switch_to_fallback(error)
        @mode = :fallback
        code = platform_error_code(error)
        if UNSUPPORTED_ERRORS.include?(code)
          adapter.instance_variable_set(:@native_streaming_broken, true)
        end
        ChatSDK::Log.warn("Slack native streaming failed; using post-and-edit fallback: #{error.message}")
      end

      def flush_fallback(force:)
        return if @accumulated.empty? || @accumulated == @fallback_sent

        now = monotonic_now
        interval = options.fetch(:update_interval, 0.5)
        return unless force || @last_fallback_edit_at.nil? || now - @last_fallback_edit_at >= interval

        if @fallback_message
          adapter.edit_message(
            channel_id: channel_id,
            message_id: @fallback_message.id,
            message: fallback_postable
          )
        elsif options[:placeholder]
          @fallback_message = adapter.post_message(
            channel_id: channel_id,
            thread_id: thread_id,
            message: ChatSDK::PostableMessage.new(
              text: options[:placeholder],
              ai_generated: options[:ai_generated] || false
            )
          )
          adapter.edit_message(
            channel_id: channel_id,
            message_id: @fallback_message.id,
            message: fallback_postable
          )
        else
          @fallback_message = adapter.post_message(
            channel_id: channel_id,
            thread_id: thread_id,
            message: fallback_postable
          )
        end
        @fallback_sent = @accumulated.dup
        @last_fallback_edit_at = now
      end

      def fallback_postable
        ChatSDK::PostableMessage.new(text: @accumulated.dup, ai_generated: options[:ai_generated] || false)
      end

      def finish_fallback
        warn_skipped_stop_blocks if options[:stop_blocks]
        message_with_text(@fallback_message, @accumulated)
      end

      def message_with_text(message, text)
        return unless message

        ChatSDK::Message.new(
          id: message.id,
          text: text.dup,
          author: message.author,
          thread_id: message.thread_id,
          channel_id: message.channel_id,
          platform: message.platform,
          attachments: message.attachments,
          links: message.links,
          reply_to: message.reply_to,
          subject: message.subject,
          raw: message.raw,
          timestamp: message.timestamp,
          is_mention: message.is_mention
        )
      end

      def warn_skipped_stop_blocks
        ChatSDK::Log.warn("Slack stream-end blocks were skipped by the post-and-edit fallback")
      end

      def build_message(id:, response:, message_ids:)
        ChatSDK::Message.new(
          id: id,
          text: @accumulated.dup,
          author: ChatSDK::Author.new(id: "bot", name: "bot", platform: :slack, bot: true),
          thread_id: thread_id,
          channel_id: channel_id,
          platform: :slack,
          raw: {
            "ts" => id,
            "message_ids" => message_ids,
            "response" => response
          }
        )
      end

      def mark_segment_started
        @segment.started_at ||= monotonic_now
        @segment.flush_next_append = false
        @native_rendered = true
      end

      def monotonic_now
        adapter.send(:monotonic_now)
      end

      def stream_error_classes
        slack_error_classes + [Faraday::Error, IOError, SocketError, Timeout::Error, ChatSDK::Error]
      end

      def slack_error_classes
        [::Slack::Web::Api::Errors::SlackError]
      end

      def platform_error_code(error)
        return unless error.is_a?(::Slack::Web::Api::Errors::SlackError)

        error.error
      rescue NoMethodError
        nil
      end

      def stream_expired?(error)
        platform_error_code(error) == STREAM_EXPIRED_ERROR
      end

      def response_value(response, key)
        return unless response.respond_to?(:[])

        response[key.to_s] || response[key] ||
          (response["message"] || response[:message])&.then { |message| message[key.to_s] || message[key] }
      end

      def segment_cut_index(text)
        paragraph_break = text.rindex("\n\n")
        return paragraph_break + 2 if paragraph_break

        (text.rindex("\n") || -1) + 1
      end

      def fence_tracker
        {open: nil}
      end

      def feed_fence(tracker, line)
        match = FENCE_PATTERN.match(line)
        return false unless match

        marker = match[1]
        info = match[2]
        if tracker[:open]
          current = tracker[:open]
          if marker[0] == current[:marker][0] && marker.length >= current[:marker].length && info.strip.empty?
            tracker[:open] = nil
            return true
          end
          return false
        end
        return false if marker.start_with?("`") && info.include?("`")

        tracker[:open] = {marker: marker, opening: line.rstrip}
        true
      end

      def open_fence_in(text)
        tracker = fence_tracker
        text.split("\n").each { |line| feed_fence(tracker, line) }
        tracker[:open]
      end

      def closes_fence?(fence, line)
        tracker = {open: fence}
        feed_fence(tracker, line)
      end

      def table_continuation(text)
        return "" unless text.end_with?("\n")

        lines = text.split("\n", -1)
        lines.pop
        rows = []
        lines.reverse_each do |line|
          break unless TABLE_ROW_PATTERN.match?(line.strip)

          rows.unshift(line)
        end
        separator_at = rows.index { |row| TABLE_SEPARATOR_PATTERN.match?(row.strip) }
        return "" unless separator_at&.positive?

        "#{rows[separator_at - 1]}\n#{rows[separator_at]}\n"
      end
    end
  end
end
