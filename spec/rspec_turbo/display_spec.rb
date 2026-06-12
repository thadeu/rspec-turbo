# frozen_string_literal: true

require "tmpdir"

RSpec.describe RSpecTurbo::Display do
  # A minimal planner stand-in: Display only reads #pending_count here.
  let(:planner) { instance_double(RSpecTurbo::BatchPlanner, pending_count: 0) }
  let(:display) { described_class.new(planner) }

  describe ".folder_for" do
    it "buckets a top-level spec file by its first segment" do
      expect(described_class.folder_for("models/user_spec.rb")).to eq("models")
    end

    it "buckets a nested file by its first two segments" do
      expect(described_class.folder_for("requests/v1/items_spec.rb")).to eq("requests/v1")
    end

    it "buckets an example-id slice (Array unit) by its file path" do
      expect(described_class.folder_for(["./spec/models/user_spec.rb[1:2]"])).to eq("models")
    end
  end

  describe "#parse_profiler_data" do
    # Exactly the block slow_profile.rb emits (with ANSI colour, which Display
    # is expected to strip) — this locks the contract between the two files.
    let(:log) do
      <<~LOG
        \e[34m#{"=" * 96}\e[0m
         \e[34mSLOW / EXPENSIVE EXAMPLES (time >= 0.2s OR queries >= 30)\e[0m
        \e[34m#{"=" * 96}\e[0m
        TIME     QUERIES FILE                  EXAMPLE
         0.500s   40     spec/models/user_spec.rb   does a thing

        \e[31m#{"=" * 96}\e[0m
         \e[31mTOP 15 FILES BY TIME\e[0m
        \e[31m#{"=" * 96}\e[0m
        TIME     QUERIES  FILE
         12.34s      5    spec/models/user_spec.rb
          3.20s      2    spec/models/post_spec.rb

      LOG
    end

    it "extracts seconds + file from the TOP FILES section only" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "worker_01.log")
        File.write(path, log)

        data = display.send(:parse_profiler_data, [path])

        expect(data).to eq([
          {seconds: 12.34, file: "spec/models/user_spec.rb"},
          {seconds: 3.2, file: "spec/models/post_spec.rb"}
        ])
      end
    end

    it "returns nothing when a log has no profiler section" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "worker_01.log")
        File.write(path, "1 example, 0 failures\n")

        expect(display.send(:parse_profiler_data, [path])).to eq([])
      end
    end
  end

  describe "#aggregate_by_folder" do
    it "sums file times into their parent folder, descending" do
      data = [
        {seconds: 10.0, file: "spec/models/user_spec.rb"},
        {seconds: 5.0, file: "spec/models/post_spec.rb"},
        {seconds: 20.0, file: "spec/requests/items_spec.rb"}
      ]

      expect(display.send(:aggregate_by_folder, data)).to eq([
        ["requests", 20.0],
        ["models", 15.0]
      ])
    end
  end
end
