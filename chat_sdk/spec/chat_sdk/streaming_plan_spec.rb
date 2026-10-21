# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

RSpec.describe ChatSDK::StreamingPlan do
  let(:source) { ["hello"] }

  it "exposes the stream and options" do
    plan = described_class.new(source, group_tasks: :plan, end_with: [{type: "context"}])

    expect(plan.stream).to be(source)
    expect(plan.options).to eq(
      group_tasks: "plan",
      end_with: [{type: "context"}],
      ai_generated: false
    )
  end

  it "maps plan options to stream options" do
    plan = described_class.new(
      source,
      group_tasks: :timeline,
      end_with: [{type: "context"}],
      update_interval: 1.5,
      ai_generated: true
    )

    expect(plan.to_stream_options).to eq(
      task_display_mode: "timeline",
      stop_blocks: [{type: "context"}],
      update_interval: 1.5,
      ai_generated: true
    )
  end

  it "omits false and unset options" do
    expect(described_class.new(source).to_stream_options).to eq({})
  end

  it "validates group_tasks" do
    expect { described_class.new(source, group_tasks: :invalid) }
      .to raise_error(ArgumentError, /group_tasks must be :plan or :timeline/)
  end
end
