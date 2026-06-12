# frozen_string_literal: true

RSpec.describe RSpecTurbo::Options do
  it "separates folders from rspec flags" do
    options = described_class.new(["spec/models", "--fail-fast", "spec/lib"])

    expect(options.folders).to eq(["spec/models", "spec/lib"])
    expect(options.rspec_options).to eq(["--fail-fast"])
  end

  it "captures the value for flags that take one" do
    options = described_class.new(["--tag", "focus", "spec/models"])

    expect(options.rspec_options).to eq(["--tag", "focus"])
    expect(options.folders).to eq(["spec/models"])
  end

  it "treats --flag=value as a single token" do
    options = described_class.new(["--seed=123", "spec"])

    expect(options.rspec_options).to eq(["--seed=123"])
    expect(options.folders).to eq(["spec"])
  end

  it "does not swallow a following flag as a value" do
    options = described_class.new(["--order", "--fail-fast"])

    expect(options.rspec_options).to eq(["--order", "--fail-fast"])
    expect(options.folders).to be_empty
  end

  describe "exclude patterns" do
    it "extracts the space-separated form" do
      options = described_class.new(["--exclude-pattern", "spec/system/**/*"])

      expect(options.exclude_patterns).to eq(["spec/system/**/*"])
    end

    it "extracts the equals form" do
      options = described_class.new(["--exclude-pattern=spec/system/**/*"])

      expect(options.exclude_patterns).to eq(["spec/system/**/*"])
    end
  end
end
