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

    def fmt_duration(seconds)
      minutes, secs = seconds.divmod(60)

      minutes.positive? ? format("%dm%02ds", minutes, secs) : format("%ds", secs)
    end

    # Wraps text in an ANSI escape sequence only when running in a TTY.
    def c(code, text) = Config::TTY ? "\e[#{code}m#{text}\e[0m" : text

    def strip_ansi(text) = text.gsub(/\e\[[0-9;]*m/, "")
  end
end
