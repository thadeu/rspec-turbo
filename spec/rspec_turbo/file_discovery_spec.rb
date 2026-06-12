# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe RSpecTurbo::FileDiscovery do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("spec/models")
        FileUtils.mkdir_p("spec/system")
        FileUtils.touch("spec/models/user_spec.rb")
        FileUtils.touch("spec/models/post_spec.rb")
        FileUtils.touch("spec/system/login_spec.rb")
        FileUtils.touch("spec/models/shared.rb")
        example.run
      end
    end
  end

  it "finds every *_spec.rb under spec/ when no folder is given" do
    files = described_class.new([]).files

    expect(files).to contain_exactly(
      "models/user_spec.rb", "models/post_spec.rb", "system/login_spec.rb"
    )
  end

  it "scopes discovery to a given folder" do
    files = described_class.new(["spec/models"]).files

    expect(files).to contain_exactly("models/user_spec.rb", "models/post_spec.rb")
  end

  it "accepts an explicit single file" do
    files = described_class.new(["spec/models/user_spec.rb"]).files

    expect(files).to eq(["models/user_spec.rb"])
  end

  it "applies exclude patterns" do
    files = described_class.new([], exclude_patterns: ["spec/system/**/*"]).files

    expect(files).to contain_exactly("models/user_spec.rb", "models/post_spec.rb")
  end

  it "de-duplicates overlapping folders" do
    files = described_class.new(["spec/models", "spec"]).files

    expect(files).to contain_exactly(
      "models/user_spec.rb", "models/post_spec.rb", "system/login_spec.rb"
    )
  end
end
