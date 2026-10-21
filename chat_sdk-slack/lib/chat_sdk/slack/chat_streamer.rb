# frozen_string_literal: true

require "json"

module ChatSDK
  module Slack
    class ChatStreamer
      attr_reader :ts

      def initialize(client, channel:, thread_ts:, recipient_user_id: nil,
        recipient_team_id: nil, task_display_mode: nil, buffer_size: 256)
        @client = client
        @stream_args = {channel: channel, thread_ts: thread_ts}
        @stream_args[:recipient_user_id] = recipient_user_id if recipient_user_id
        @stream_args[:recipient_team_id] = recipient_team_id if recipient_team_id
        @stream_args[:task_display_mode] = task_display_mode if task_display_mode
        @buffer_size = buffer_size
        @buffer = +""
        @state = :starting
        @token = nil
        @ts = nil
      end

      def append(markdown_text: nil, chunks: nil, **options)
        ensure_open!(:append)
        @token = options.delete(:token) if options[:token]
        @buffer << markdown_text if markdown_text && !markdown_text.empty?
        return unless @buffer.length >= @buffer_size || !chunks.nil?

        flush_buffer(chunks, options)
      end

      def stop(markdown_text: nil, chunks: nil, blocks: nil, **options)
        ensure_open!(:stop)
        @token = options.delete(:token) if options[:token]
        @buffer << markdown_text if markdown_text && !markdown_text.empty?

        start_stream unless ts

        stop_chunks = chunks_for_flush(chunks)
        params = {
          token: @token,
          channel: @stream_args[:channel],
          ts: ts,
          chunks: JSON.generate(stop_chunks)
        }
        params[:blocks] = JSON.generate(blocks) if blocks
        params.merge!(options)
        response = call_api(:chat_stopStream, "chat.stopStream", params)
        @buffer.clear
        @state = :completed
        response
      end

      private

      def flush_buffer(chunks, options)
        payload = chunks_for_flush(chunks)
        params = {
          token: @token,
          chunks: JSON.generate(payload)
        }.merge(options)

        if ts
          params[:channel] = @stream_args[:channel]
          params[:ts] = ts
          response = call_api(:chat_appendStream, "chat.appendStream", params)
        else
          response = call_api(
            :chat_startStream,
            "chat.startStream",
            @stream_args.merge(params)
          )
          @ts = response_value(response, :ts)
          @state = :in_progress
        end

        @buffer.clear
        response
      end

      def start_stream
        response = call_api(
          :chat_startStream,
          "chat.startStream",
          @stream_args.merge(token: @token)
        )
        @ts = response_value(response, :ts)
        raise ChatSDK::Error, "failed to stop stream: stream not started" unless ts

        @state = :in_progress
      end

      def chunks_for_flush(chunks)
        payload = []
        unless @buffer.empty?
          payload << {type: "markdown_text", text: @buffer}
        end
        Array(chunks).each do |chunk|
          payload << (chunk.respond_to?(:to_h) ? chunk.to_h : chunk)
        end
        payload
      end

      def call_api(method, endpoint, params)
        if @client.respond_to?(method)
          @client.public_send(method, **params)
        else
          @client.post(endpoint, params)
        end
      end

      def response_value(response, key)
        response[key.to_s] || response[key]
      end

      def ensure_open!(action)
        return unless @state == :completed

        raise ChatSDK::Error, "failed to #{action} stream: stream state is #{@state}"
      end
    end
  end
end
