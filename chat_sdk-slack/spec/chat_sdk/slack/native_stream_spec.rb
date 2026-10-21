# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::Slack::Adapter do
  let(:calls) { [] }
  let(:clock) { [0.0] }
  let(:client) { instance_double(::Slack::Web::Client) }
  let(:adapter) { build_adapter }

  before do
    allow(client).to receive(:chat_startStream) do |**params|
      calls << [:start, params]
      {"ts" => "S#{calls.count { |call| call.first == :start }}"}
    end
    allow(client).to receive(:chat_appendStream) do |**params|
      calls << [:append, params]
      {"ok" => true}
    end
    allow(client).to receive(:chat_stopStream) do |**params|
      calls << [:stop, params]
      {"ts" => params[:ts]}
    end
    allow(client).to receive(:chat_postMessage) do |**params|
      calls << [:post_message, params]
      {"ts" => "F1"}
    end
    allow(client).to receive(:chat_update) do |**params|
      calls << [:update, params]
      {"ok" => true}
    end
  end

  describe "#initialize streaming options" do
    it "accepts positive finite ages and infinity" do
      expect { build_adapter(stream_segment_max_age: 2.5) }.not_to raise_error
      expect { build_adapter(stream_segment_max_age: Float::INFINITY) }.not_to raise_error
    end

    it "rejects non-positive and non-real ages" do
      [0, -1, Float::NAN, Complex(1, 2)].each do |value|
        expect { build_adapter(stream_segment_max_age: value) }
          .to raise_error(ChatSDK::ConfigurationError, /stream_segment_max_age/)
      end
    end
  end

  describe "native stream eligibility" do
    it "returns nil without consuming the stream when thread_id is missing" do
      consumed = false
      source = Enumerator.new do |yielder|
        consumed = true
        yielder << "hello"
      end

      expect(run_stream(source, thread_id: nil)).to be_nil
      expect(consumed).to be(false)
    end

    it "returns nil without consuming a non-DM stream without both recipients" do
      consumed = false
      source = Enumerator.new do |yielder|
        consumed = true
        yielder << "hello"
      end

      expect(run_stream(source, options: {})).to be_nil
      expect(consumed).to be(false)
    end

    it "treats empty recipient IDs as missing" do
      consumed = false
      source = Enumerator.new do |yielder|
        consumed = true
        yielder << "hello"
      end

      expect(run_stream(source, options: native_options.merge(recipient_user_id: ""))).to be_nil
      expect(consumed).to be(false)
    end

    it "returns nil without consuming when native streaming is disabled" do
      consumed = false
      disabled_adapter = build_adapter(native_streaming: false)
      source = Enumerator.new do |yielder|
        consumed = true
        yielder << "hello"
      end

      expect(disabled_adapter.stream(
        channel_id: "C123",
        thread_id: "T123",
        stream: source,
        options: native_options
      )).to be_nil
      expect(consumed).to be(false)
    end

    it "returns nil without consuming after an unsupported-method error is latched" do
      adapter.instance_variable_set(:@native_streaming_broken, true)
      consumed = false
      source = Enumerator.new do |yielder|
        consumed = true
        yielder << "hello"
      end

      expect(run_stream(source)).to be_nil
      expect(consumed).to be(false)
    end

    it "streams a DM without recipient IDs" do
      result = run_stream(["hello"], channel_id: "D123", options: {})

      expect(result).to be_a(ChatSDK::Message)
      expect(calls.map(&:first)).to eq(%i[start stop])
      expect(calls.first.last).not_to have_key(:recipient_user_id)
    end
  end

  describe "native API calls" do
    it "starts, appends, and stops with JSON chunks, blocks, and recipient options" do
      text = "x" * 256
      stop_blocks = [{type: "context", elements: []}]
      result = run_stream(
        [text, text],
        options: native_options.merge(task_display_mode: "plan", stop_blocks: stop_blocks)
      )

      expect(calls.map(&:first)).to eq(%i[start append stop])
      expect(JSON.parse(calls[0].last[:chunks])).to eq([{"type" => "markdown_text", "text" => text}])
      expect(JSON.parse(calls[1].last[:chunks])).to eq([{"type" => "markdown_text", "text" => text}])
      expect(calls[0].last).to include(
        channel: "C123",
        thread_ts: "T123",
        recipient_user_id: "U123",
        recipient_team_id: "T123",
        task_display_mode: "plan"
      )
      expect(JSON.parse(calls.last.last[:chunks])).to eq([])
      expect(JSON.parse(calls.last.last[:blocks])).to eq(stop_blocks.map { |block| block.transform_keys(&:to_s) })
      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("S1")
      expect(result.text).to eq(text * 2)
      expect(result.raw["message_ids"]).to eq(["S1"])
    end

    it "flushes text before sending structured task and plan chunks" do
      text = "x" * 256
      task = ChatSDK::Streaming::TaskUpdateChunk.new(
        id: "task-1", title: "Check", status: "in_progress"
      )
      plan = ChatSDK::Streaming::PlanUpdateChunk.new(title: "Plan")

      run_stream([text, task, plan])

      expect(calls.map(&:first)).to eq(%i[start append append stop])
      expect(JSON.parse(calls[0].last[:chunks])).to eq([{"type" => "markdown_text", "text" => text}])
      expect(JSON.parse(calls[1].last[:chunks])).to eq([task.to_h.transform_keys(&:to_s)])
      expect(JSON.parse(calls[2].last[:chunks])).to eq([plan.to_h.transform_keys(&:to_s)])
    end

    it "disables rejected structured chunks while continuing to send text" do
      text = "x" * 256
      task = ChatSDK::Streaming::TaskUpdateChunk.new(
        id: "task-1", title: "Check", status: "pending"
      )
      task_rejected = false
      allow(client).to receive(:chat_appendStream) do |**params|
        calls << [:append, params]
        if JSON.parse(params[:chunks]).any? { |chunk| chunk["type"] == "task_update" }
          task_rejected = true
          raise slack_error("missing_scope")
        end
        {"ok" => true}
      end

      result = run_stream([text, task, text])

      expect(task_rejected).to be(true)
      expect(result.text).to eq(text * 2)
      expect(calls.count { |call| call.first == :append }).to eq(2)
    end
  end

  describe "client token resolution" do
    it "uses the installation client selected by the event context" do
      adapter = build_multi_workspace_adapter
      adapter.parse_events(event_callback_request("T2"))
      expect(adapter).to receive(:client_for_token).with("xoxb-t2").once.and_return(client)

      result = adapter.stream(
        channel_id: "D123",
        thread_id: "T123",
        stream: ["hello"],
        options: {}
      )

      expect(result.text).to eq("hello")
      expect(calls.map(&:first)).to eq(%i[start stop])
    end

    it "reuses the installation client when rotating native stream segments" do
      adapter = build_multi_workspace_adapter
      adapter.parse_events(event_callback_request("T2"))
      expect(adapter).to receive(:client_for_token).with("xoxb-t2").once.and_return(client)
      source = Enumerator.new do |yielder|
        yielder << "x" * 256
        clock[0] = 270
        yielder << "\n\ncontinued"
      end

      adapter.stream(
        channel_id: "D123",
        thread_id: "T123",
        stream: source,
        options: {}
      )

      expect(calls.count { |call| call.first == :start }).to eq(2)
    end

    it "uses the token scoped with with_bot_token" do
      adapter = build_multi_workspace_adapter
      expect(adapter).to receive(:client_for_token).with("xoxb-t2").once.and_return(client)

      adapter.with_bot_token("xoxb-t2") do
        adapter.stream(
          channel_id: "D123",
          thread_id: "T123",
          stream: ["hello"],
          options: {}
        )
      end

      expect(calls.map(&:first)).to eq(%i[start stop])
    end

    it "uses the resolved client from a bot_token callable" do
      adapter = described_class.new(
        bot_token: -> { "xoxb-resolved" },
        signing_secret: "test-signing-secret"
      )
      expect(adapter).to receive(:client_for_token).with("xoxb-resolved").once.and_return(client)

      result = adapter.stream(
        channel_id: "D123",
        thread_id: "T123",
        stream: ["hello"],
        options: {}
      )

      expect(result.text).to eq("hello")
      expect(calls.map(&:first)).to eq(%i[start stop])
    end
  end

  describe "fallback" do
    it "uses post-and-edit when the first native call fails and permanently latches unsupported methods" do
      text = "x" * 256
      allow(client).to receive(:chat_startStream).and_raise(
        slack_error("unknown_method", klass: ::Slack::Web::Api::Errors::UnknownMethod)
      )

      result = run_stream([text, " tail"])

      expect(result).to be_a(ChatSDK::Message)
      expect(result.text).to eq("#{text} tail")
      expect(calls.map(&:first)).to include(:post_message, :update)
      expect(calls.find { |call| call.first == :update }.last[:text]).to eq("#{text} tail")
      expect(adapter.instance_variable_get(:@native_streaming_broken)).to be(true)

      consumed = false
      source = Enumerator.new do |yielder|
        consumed = true
        yielder << "later"
      end
      expect(run_stream(source)).to be_nil
      expect(consumed).to be(false)
    end

    it "falls back after a stop-time first native call failure" do
      allow(client).to receive(:chat_startStream).and_raise(slack_error("ratelimited"))

      result = run_stream(["short"])

      expect(result).to be_a(ChatSDK::Message)
      expect(calls.map(&:first)).to include(:post_message)
      expect(adapter.instance_variable_get(:@native_streaming_broken)).to be(false)
    end

    it "does not latch transient errors" do
      allow(client).to receive(:chat_startStream).and_raise(slack_error("ratelimited"))

      run_stream(["short"])

      expect(adapter.instance_variable_get(:@native_streaming_broken)).to be(false)
    end

    it "propagates native failures after a message has rendered" do
      allow(client).to receive(:chat_appendStream).and_raise(slack_error("internal_error"))

      expect { run_stream(["x" * 256, "y" * 256]) }
        .to raise_error(::Slack::Web::Api::Errors::SlackError, /internal_error/)
      expect(calls.map(&:first)).not_to include(:post_message)
    end

    it "skips structured chunks after switching to fallback" do
      text = "x" * 256
      task = ChatSDK::Streaming::TaskUpdateChunk.new(id: "task-1", title: "Task", status: "pending")
      allow(client).to receive(:chat_startStream).and_raise(slack_error("ratelimited"))

      result = run_stream([text, task, "tail"])

      expect(result).to be_a(ChatSDK::Message)
      expect(calls.map(&:first)).not_to include(:append)
      expect(calls.find { |call| call.first == :update }.last[:text]).to eq("#{text}tail")
    end
  end

  describe "stream rotation" do
    it "rotates at a paragraph boundary and reopens an open code fence" do
      first = "```ruby\n" + ("x" * 248)
      expect(first.length).to eq(256)
      source = Enumerator.new do |yielder|
        yielder << first
        clock[0] = 240
        yielder << "\n\nputs :done\n"
      end

      result = run_stream(source)

      expect(calls.map(&:first)).to eq(%i[start stop start stop])
      expect(result.raw["message_ids"]).to eq(%w[S1 S2])
      expect(JSON.parse(calls[2].last[:chunks])).to eq([
        {"type" => "markdown_text", "text" => "```ruby\nputs :done\n"}
      ])
    end

    it "does not rotate when no new content arrives" do
      source = Enumerator.new do |yielder|
        yielder << ("x" * 256)
        clock[0] = 240
      end

      run_stream(source)

      expect(calls.map(&:first)).to eq(%i[start stop])
    end

    it "continues in a new message when the segment expires before rotation" do
      stop_calls = 0
      allow(client).to receive(:chat_stopStream) do |**params|
        calls << [:stop, params]
        stop_calls += 1
        raise slack_error("message_not_in_streaming_state") if stop_calls == 1

        {"ts" => params[:ts]}
      end
      source = Enumerator.new do |yielder|
        yielder << ("x" * 256)
        clock[0] = 240
        yielder << "\n\nnext"
      end

      result = run_stream(source)

      expect(calls.map(&:first)).to eq(%i[start stop start stop])
      expect(result.raw["message_ids"]).to eq(%w[S1 S2])
      expect(result.text).to eq("#{"x" * 256}\n\nnext")
    end

    it "recovers unconfirmed text when the final segment expires before stop" do
      allow(client).to receive(:chat_stopStream) do |**params|
        calls << [:stop, params]
        raise slack_error("message_not_in_streaming_state") if params[:ts] == "S1"

        {"ts" => params[:ts]}
      end

      result = run_stream(["x" * 256, " pending"])

      expect(calls.map(&:first)).to eq(%i[start stop start stop])
      expect(result.id).to eq("S2")
      expect(result.raw["message_ids"]).to eq(%w[S1 S2])
      expect(JSON.parse(calls.last.last[:chunks])).to eq([
        {"type" => "markdown_text", "text" => " pending"}
      ])
    end

    it "returns the expired message when all text was delivered before stop" do
      allow(client).to receive(:chat_stopStream) do |**params|
        calls << [:stop, params]
        raise slack_error("message_not_in_streaming_state")
      end

      result = run_stream(["x" * 256])

      expect(result.id).to eq("S1")
      expect(result.raw["message_ids"]).to eq(["S1"])
      expect(calls.map(&:first)).to eq(%i[start stop])
    end

    it "raises the original expiry error when an expired segment has no timestamp" do
      start_calls = 0
      allow(client).to receive(:chat_startStream) do |**params|
        calls << [:start, params]
        start_calls += 1
        raise slack_error("message_not_in_streaming_state") if start_calls == 2

        {}
      end

      expect { run_stream(["x" * 256]) }
        .to raise_error(::Slack::Web::Api::Errors::SlackError, /message_not_in_streaming_state/)
      expect(calls.map(&:first)).to eq(%i[start start])
    end

    it "propagates non-expiry errors during rotation" do
      allow(client).to receive(:chat_stopStream) do |**params|
        calls << [:stop, params]
        raise slack_error("ratelimited")
      end
      source = Enumerator.new do |yielder|
        yielder << ("x" * 256)
        clock[0] = 240
        yielder << "\n\nnext"
      end

      expect { run_stream(source) }
        .to raise_error(::Slack::Web::Api::Errors::SlackError, /ratelimited/)
      expect(calls.map(&:first)).to eq(%i[start stop])
    end

    it "completes open task cards and replays them into the next segment" do
      task = ChatSDK::Streaming::TaskUpdateChunk.new(
        id: "task-1", title: "Check", status: "in_progress"
      )
      source = Enumerator.new do |yielder|
        yielder << task
        yielder << ("x" * 256)
        clock[0] = 240
        yielder << "\n\nnext"
      end

      run_stream(source)

      rotation_stop = calls.find { |call| call.first == :stop }.last
      expect(JSON.parse(rotation_stop[:chunks])).to include(
        include("type" => "task_update", "id" => "task-1", "status" => "complete")
      )
      new_segment_start = calls.reverse.find { |call| call.first == :start }.last
      expect(JSON.parse(new_segment_start[:chunks])).to include(
        include("type" => "task_update", "id" => "task-1", "status" => "in_progress")
      )
    end

    it "retries a rejected rotation stop without structured task chunks" do
      task = ChatSDK::Streaming::TaskUpdateChunk.new(
        id: "task-1", title: "Check", status: "in_progress"
      )
      stop_calls = 0
      allow(client).to receive(:chat_stopStream) do |**params|
        calls << [:stop, params]
        stop_calls += 1
        raise slack_error("invalid_arguments") if stop_calls == 1

        {"ts" => params[:ts]}
      end
      source = Enumerator.new do |yielder|
        yielder << task
        yielder << ("x" * 256)
        clock[0] = 240
        yielder << "\n\nnext"
      end

      run_stream(source)

      stops = calls.select { |call| call.first == :stop }.map(&:last)
      expect(stops.length).to eq(3)
      expect(JSON.parse(stops.first[:chunks])).to include(
        include("type" => "task_update", "status" => "complete")
      )
      expect(JSON.parse(stops[1][:chunks])).not_to include(
        include("type" => "task_update")
      )
    end

    it "does not retry rotation stops after maybe-applied or transport errors" do
      [slack_error("internal_error"), Faraday::ConnectionFailed.new("connection failed")].each do |error|
        calls.clear
        clock[0] = 0
        stop_calls = 0
        allow(client).to receive(:chat_stopStream) do |**params|
          calls << [:stop, params]
          stop_calls += 1
          raise error
        end
        source = Enumerator.new do |yielder|
          yielder << ("x" * 256)
          clock[0] = 240
          yielder << "\n\nnext"
        end

        expect { run_stream(source) }.to raise_error(error.class)
        expect(stop_calls).to eq(1)
      end
    end

    it "does not rotate before Slack starts the segment" do
      source = Enumerator.new do |yielder|
        yielder << "short"
        clock[0] = 1_000
        yielder << "\n\nnext"
      end

      run_stream(source)

      expect(calls.map(&:first)).to eq(%i[start stop])
      expect(JSON.parse(calls.last.last[:chunks])).to eq([
        {"type" => "markdown_text", "text" => "short\n\nnext"}
      ])
    end

    it "does not rotate with an infinite segment age" do
      infinite_adapter = build_adapter(stream_segment_max_age: Float::INFINITY)
      allow(infinite_adapter).to receive(:monotonic_now) { clock.fetch(0) }
      source = Enumerator.new do |yielder|
        yielder << ("x" * 256)
        clock[0] = 1_000
        yielder << "\n\nnext"
      end

      infinite_adapter.stream(
        channel_id: "C123",
        thread_id: "T123",
        stream: source,
        options: native_options
      )

      expect(calls.map(&:first)).to eq(%i[start stop])
    end

    it "repeats a table header when continuing a table after rotation" do
      header = "| Name | Value |\n| --- | --- |\n| one | "
      first = header + ("x" * (255 - header.length)) + "|"
      source = Enumerator.new do |yielder|
        yielder << first
        clock[0] = 270
        yielder << "\n| two | y |\n| three | z |"
      end

      run_stream(source)

      new_segment = calls.reverse.find { |call| call.first == :start }.last
      expect(JSON.parse(new_segment[:chunks])).to eq([
        {"type" => "markdown_text", "text" => "| Name | Value |\n| --- | --- |\n| three | z |"}
      ])
    end
  end

  def build_adapter(native_streaming: true, stream_segment_max_age: 240)
    instance = described_class.new(
      bot_token: "xoxb-test-token",
      signing_secret: "test-signing-secret",
      native_streaming: native_streaming,
      stream_segment_max_age: stream_segment_max_age
    )
    allow(instance).to receive(:client).and_return(client)
    allow(instance).to receive(:monotonic_now) { clock.fetch(0) }
    instance
  end

  def build_multi_workspace_adapter
    instance = described_class.new(
      client_id: "test-client-id",
      client_secret: "test-client-secret",
      signing_secret: "test-signing-secret"
    )
    instance.set_state(ChatSDK::State::Memory.new)
    instance.set_installation("T1", bot_token: "xoxb-t1", bot_user_id: "B_T1")
    instance.set_installation("T2", bot_token: "xoxb-t2", bot_user_id: "B_T2")
    allow(instance).to receive(:monotonic_now) { clock.fetch(0) }
    instance
  end

  def event_callback_request(team_id)
    payload = {
      "type" => "event_callback",
      "team_id" => team_id,
      "event" => {
        "type" => "message",
        "user" => "U123",
        "text" => "hello",
        "ts" => "1234567890.123456",
        "channel" => "D123",
        "channel_type" => "im"
      }
    }
    env = Rack::MockRequest.env_for(
      "/slack/events",
      :method => "POST",
      :input => JSON.generate(payload),
      "CONTENT_TYPE" => "application/json"
    )
    Rack::Request.new(env)
  end

  def run_stream(source, channel_id: "C123", thread_id: "T123", options: native_options)
    adapter.stream(
      channel_id: channel_id,
      thread_id: thread_id,
      stream: source,
      options: options
    )
  end

  def native_options
    {recipient_user_id: "U123", recipient_team_id: "T123"}
  end

  def slack_error(code, klass: ::Slack::Web::Api::Errors::SlackError)
    body = Struct.new(:error).new(code)
    response = Struct.new(:body).new(body)
    klass.new("Slack API error: #{code}", response)
  end
end
