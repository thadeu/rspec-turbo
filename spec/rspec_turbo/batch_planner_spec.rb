# frozen_string_literal: true

require "tmpdir"

RSpec.describe RSpecTurbo::BatchPlanner do
  # The dry-run shells out to rspec, so the example-balancing logic is tested
  # directly by injecting known counts and calling the (private) packers.
  def planner_with(files, workers, counts)
    planner = described_class.new(files, num_workers: workers)
    planner.instance_variable_set(:@counts, counts)
    planner
  end

  describe "bin packing (LPT)" do
    it "balances files across workers by example count" do
      counts = {"a" => 10, "b" => 5, "c" => 5, "d" => 1}
      planner = planner_with(counts.keys, 2, counts)

      units = planner.send(:build_units, counts.keys, counts, {})
      batches = planner.send(:bin_pack, units)
      totals = batches.map { |batch| planner.example_count(batch) }

      expect(batches.size).to eq(2)
      expect(totals.sum).to eq(21)
      expect(totals.max - totals.min).to be <= 1
    end

    it "never creates more buckets than there are units" do
      counts = {"only" => 1}
      planner = planner_with(counts.keys, 8, counts)

      units = planner.send(:build_units, counts.keys, counts, {})

      expect(planner.send(:bin_pack, units).size).to eq(1)
    end
  end

  describe "splitting oversized files" do
    it "slices a file heavier than the fair share into example-id units" do
      counts = {"big" => 10}
      ids = {"big" => (1..10).map { |i| "./spec/big_spec.rb[1:#{i}]" }}
      planner = planner_with(["big"], 4, counts)

      units = planner.send(:build_units, ["big"], counts, ids)

      expect(units.size).to be > 1
      expect(units).to all(be_an(Array))
      expect(units.flatten.size).to eq(10)
    end

    it "keeps files at or below the fair share whole" do
      counts = {"small" => 2, "other" => 2}
      ids = {"small" => ["./spec/small_spec.rb[1:1]", "./spec/small_spec.rb[1:2]"]}
      planner = planner_with(counts.keys, 2, counts)

      units = planner.send(:build_units, counts.keys, counts, ids)

      expect(units).to contain_exactly("small", "other")
    end
  end

  describe "#example_count" do
    it "weighs string units by their counts and array units by size" do
      planner = planner_with(["a"], 2, {"a" => 7})

      expect(planner.example_count(["a"])).to eq(7)
      expect(planner.example_count([%w[id1 id2 id3]])).to eq(3)
    end
  end

  describe "dry-run" do
    around do |example|
      Dir.mktmpdir do |dir|
        previous = ENV["RSPEC_TURBO_LOG_DIR"]
        ENV["RSPEC_TURBO_LOG_DIR"] = dir
        example.run
      ensure
        ENV["RSPEC_TURBO_LOG_DIR"] = previous
      end
    end

    let(:json) do
      {
        examples: [
          {file_path: "./spec/a_spec.rb", id: "./spec/a_spec.rb[1:1]"},
          {file_path: "./spec/a_spec.rb", id: "./spec/a_spec.rb[1:2]"},
          {file_path: "./spec/b_spec.rb", id: "./spec/b_spec.rb[1:1]"}
        ],
        summary: {pending_count: 1}
      }.to_json
    end

    it "reads the JSON from --out, whatever else lands on stdout" do
      allow(IO).to receive(:popen) do |cmd, **|
        File.write(cmd[cmd.index("--out") + 1], json)

        "#{json}Coverage report generated for RSpec to coverage.\nLine Coverage: 100.0%\n"
      end

      planner = described_class.new(%w[a_spec.rb b_spec.rb], num_workers: 2).plan!

      expect(planner.counts).to eq("a_spec.rb" => 2, "b_spec.rb" => 1)
      expect(planner.pending_count).to eq(1)
    end

    it "counts shared examples for the spec file that includes them" do
      shared = {
        examples: [
          {file_path: "./spec/support/shared_examples/adapter.rb", id: "./spec/a_spec.rb[1:1:1]"},
          {file_path: "./spec/a_spec.rb", id: "./spec/a_spec.rb[1:2]"}
        ],
        summary: {pending_count: 0}
      }.to_json

      allow(IO).to receive(:popen) do |cmd, **|
        File.write(cmd[cmd.index("--out") + 1], shared)

        ""
      end

      planner = described_class.new(%w[a_spec.rb], num_workers: 1).plan!

      expect(planner.counts).to eq("a_spec.rb" => 2)
    end

    it "falls back to equal weights when rspec writes no JSON" do
      allow(IO).to receive(:popen).and_return("")

      planner = nil

      expect { planner = described_class.new(%w[a_spec.rb], num_workers: 2).plan! }
        .to output(/No JSON in dry-run output/).to_stderr

      expect(planner.counts).to eq({})
      expect(planner.batches).to eq([["a_spec.rb"]])
    end
  end
end
