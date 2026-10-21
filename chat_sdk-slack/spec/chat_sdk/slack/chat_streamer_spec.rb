# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::Slack::ChatStreamer do
  it "uses client stream methods and JSON encodes payloads" do
    client = instance_double(::Slack::Web::Client)
    allow(client).to receive_messages(
      chat_startStream: {"ts" => "S1"},
      chat_appendStream: {"ok" => true},
      chat_stopStream: {"ts" => "S1"}
    )
    streamer = described_class.new(client, channel: "C1", thread_ts: "T1")
    text = "x" * 256

    streamer.append(markdown_text: text)
    streamer.stop(blocks: [{type: "context"}])

    expect(client).to have_received(:chat_startStream).with(
      hash_including(chunks: JSON.generate([{type: "markdown_text", text: text}]))
    )
    expect(client).to have_received(:chat_stopStream).with(
      hash_including(chunks: "[]", blocks: JSON.generate([{type: "context"}]))
    )
  end

  it "falls back to client.post when stream methods are unavailable" do
    requests = []
    client = double("Slack client")
    allow(client).to receive(:post) do |endpoint, params|
      requests << [endpoint, params]
      {"ts" => "S1"}
    end
    streamer = described_class.new(client, channel: "C1", thread_ts: "T1")

    streamer.append(markdown_text: "hello")
    streamer.stop

    expect(requests.map(&:first)).to eq(["chat.startStream", "chat.stopStream"])
    expect(requests.first.last).not_to have_key(:chunks)
    expect(JSON.parse(requests.last.last[:chunks])).to eq([{"type" => "markdown_text", "text" => "hello"}])
  end
end
