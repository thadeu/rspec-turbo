# frozen_string_literal: true

RSpec.describe RSpecTurbo::Terminal do
  describe ".fmt_duration" do
    it "renders sub-minute durations as seconds" do
      expect(described_class.fmt_duration(5)).to eq("5s")
    end

    it "renders minute-plus durations as zero-padded m/s" do
      expect(described_class.fmt_duration(65)).to eq("1m05s")
      expect(described_class.fmt_duration(600)).to eq("10m00s")
    end
  end

  describe ".strip_ansi" do
    it "removes colour escape sequences" do
      expect(described_class.strip_ansi("\e[31mred\e[0m text")).to eq("red text")
    end

    it "leaves plain text untouched" do
      expect(described_class.strip_ansi("plain")).to eq("plain")
    end
  end
end
