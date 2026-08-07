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

  describe ".sanitize" do
    it "drops an OSC 52 clipboard write" do
      expect(described_class.sanitize("\e]52;c;aGVsbG8=\a")).to eq("")
    end

    it "drops an OSC sequence terminated by ST" do
      expect(described_class.sanitize("\e]0;title\e\\")).to eq("")
    end

    it "strips non-m CSI final bytes whole" do
      expect(described_class.sanitize("\e[2Jcleared")).to eq("cleared")
    end

    it "removes carriage-return overwrite controls" do
      expect(described_class.sanitize("visible\rHIDDEN")).to eq("visibleHIDDEN")
    end

    it "drops 8-bit C1 introducers" do
      expect(described_class.sanitize("\u009Bhi")).to eq("hi")
    end

    it "removes bidi override characters" do
      expect(described_class.sanitize("safe\u202Eemas")).to eq("safeemas")
    end

    it "preserves newlines and tabs" do
      expect(described_class.sanitize("a\tb\nc")).to eq("a\tb\nc")
    end

    it "still drops ESC from an unterminated OSC" do
      result = described_class.sanitize("\e]52;c;partial")

      expect(result).not_to include("\e")
      expect(result).to eq("]52;c;partial")
    end
  end
end
