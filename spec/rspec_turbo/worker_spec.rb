# frozen_string_literal: true

RSpec.describe RSpecTurbo::Worker do
  around do |example|
    saved = ENV.values_at("RSPEC_TURBO_NO_PROFILE", "RSPEC_PROFILE_SLOW")
    ENV.delete("RSPEC_TURBO_NO_PROFILE")
    ENV.delete("RSPEC_PROFILE_SLOW")
    example.run
    ENV["RSPEC_TURBO_NO_PROFILE"], ENV["RSPEC_PROFILE_SLOW"] = saved
  end

  describe ".profile_env (profiling on by default)" do
    it "enables slow profiling in the child by default" do
      expect(described_class.send(:profile_env)).to eq("RSPEC_PROFILE_SLOW" => "1")
    end

    it "hard-unsets the profiler envs when RSPEC_TURBO_NO_PROFILE=1" do
      ENV["RSPEC_TURBO_NO_PROFILE"] = "1"

      expect(described_class.send(:profile_env)).to eq(
        "RSPEC_PROFILE_SLOW" => nil, "RSPEC_PROFILE_GROUP_BY" => nil
      )
    end

    it "respects an explicit RSPEC_PROFILE_SLOW value" do
      ENV["RSPEC_PROFILE_SLOW"] = "detailed"

      expect(described_class.send(:profile_env)).to eq("RSPEC_PROFILE_SLOW" => "detailed")
    end
  end

  describe ".rspec_args" do
    it "prefixes plain file units with spec/ and passes id slices through" do
      args = described_class.send(:rspec_args, ["models/user_spec.rb", ["./spec/big_spec.rb[1:1]"]])

      expect(args).to eq(["spec/models/user_spec.rb", "./spec/big_spec.rb[1:1]"])
    end
  end
end
