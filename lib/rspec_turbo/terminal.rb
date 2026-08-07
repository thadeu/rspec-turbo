# frozen_string_literal: true

module RSpecTurbo
  # Pure presentation helpers shared across the reporting code: duration
  # formatting, optional ANSI colour, spinner frames and rule separators.
  #
  # On CI (no TTY) colour is dropped and box-drawing characters fall back to
  # plain ASCII, which CI log viewers render without mangling.
  module Terminal
    module_function

    SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

    SEP_THIN = (Config::TTY ? "─" : "=") * 68
    SEP_THICK = (Config::TTY ? "═" : "=") * 68

    # ANSI CSI sequence: ESC [ params intermediates final-byte.
    CSI_SEQUENCE = /\e\[[\x30-\x3F]*[\x20-\x2F]*[\x40-\x7E]/
    # OSC sequence: ESC ] payload, terminated by BEL or ST. Bounded so an
    # unterminated sequence cannot drag the scan across the whole buffer.
    OSC_SEQUENCE = /\e\][^\a\e]{0,4096}(?:\a|\e\\)/
    # Safety net for anything the two patterns above did not consume: every C0
    # control except newline and tab, DEL, the whole C1 range, and the
    # zero-width and bidi-override characters used to spoof text direction.
    UNSAFE_CHARS = /[\u0000-\u0008\u000B-\u001F\u007F-\u009F\u200B-\u200F\u2028-\u202E\u2066-\u2069]/

    def fmt_duration(seconds)
      minutes, secs = seconds.divmod(60)

      minutes.positive? ? format("%dm%02ds", minutes, secs) : format("%ds", secs)
    end

    # Wraps text in an ANSI escape sequence only when running in a TTY.
    def c(code, text) = Config::TTY ? "\e[#{code}m#{text}\e[0m" : text

    # Cosmetic only: removes well-formed sequences whole, so stripped log text
    # reads cleanly instead of leaving "[31m" litter behind.
    def strip_ansi(text) = text.gsub(CSI_SEQUENCE, "").gsub(OSC_SEQUENCE, "")

    # Security boundary. Everything printed to the terminal that originated
    # outside this gem — worker logs, spec file paths — must pass through here.
    # Dropping ESC itself defeats every escape-sequence family at once (CSI,
    # OSC, DCS, APC, PM, SOS) rather than enumerating each shape.
    def sanitize(text) = strip_ansi(text).gsub(UNSAFE_CHARS, "")
  end
end
