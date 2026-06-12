# frozen_string_literal: true

module RSpecTurbo
  # Runs the planned batches across a fixed pool of slots: one Worker per free
  # slot at a time, slots recycled as workers finish until the queue drains.
  #
  # Renders a live multi-line dashboard on a TTY (per-worker spinner lines plus
  # a global progress bar) and periodic single-line [progress] updates on CI.
  class Executor
    attr_reader :wall_started

    def initialize(planner, display, rspec_options)
      @planner = planner
      @display = display
      @rspec_options = rspec_options
      @labels = planner.batches.each_index.map { |i| format("worker/%02d", i + 1) }
      @slots = (1..planner.batches.size).to_a
      @total_examples = planner.counts.values.sum
    end

    def run
      pending = Queue.new
      @planner.batches.each_with_index { |units, i| pending << [@labels[i], units] }

      results = []
      @wall_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      if Config::TTY
        run_tty(pending, results)
      else
        run_plain(pending, results)
      end

      results
    end

    private

    def run_tty(pending, results)
      n = @labels.size
      live = live_state
      mutex = Mutex.new
      frame = 0
      spinning = true
      max_done = 0

      (n + 2).times { puts }  # reserve N worker lines + blank + progress bar

      print "\e[?25l"
      Signal.trap("INT") {
        print "\e[?25h"
        exit 130
      }
      Signal.trap("TERM") {
        print "\e[?25h"
        exit 143
      }

      spinner = Thread.new do
        while spinning
          sleep 0.1
          mutex.synchronize do
            done = @slots.sum { |s| read_progress(Config.progress_path(s)) }
            max_done = done if done > max_done
            repaint(live, frame, n, max_done)
            frame += 1
          end
        end
      end

      run_pool(pending, results) do |event, worker, result|
        mutex.synchronize do
          case event
          when :started then live[worker.label].merge!(status: :running, started: worker.started)
          when :done then live[worker.label].merge!(status: :done, duration: result[:duration], result: result[:status])
          end
        end
      end

      spinning = false
      spinner.join
      mutex.synchronize { repaint(live, frame, n, @total_examples) }
      cleanup_progress
      print "\e[?25h"
    end

    def run_plain(pending, results)
      total_workers = @planner.batches.size
      active = true
      interval = Config.progress_interval
      completed = 0

      puts Terminal::SEP_THICK
      puts "  RSpec Turbo - CI Progress"
      puts Terminal::SEP_THICK
      puts
      puts "  [progress] 0s  0/#{@total_examples} examples  0%  (0/#{total_workers} workers done)"
      $stdout.flush

      ticker = Thread.new do
        ticks = 0

        while active
          sleep 1
          ticks += 1
          next unless (ticks % interval).zero?

          done = @slots.sum { |s| read_progress(Config.progress_path(s)) }
          pct = @total_examples.positive? ? "#{(done.to_f / @total_examples * 100).round}%" : "?"
          wall = Terminal.fmt_duration(elapsed_since(@wall_started))
          puts "  [progress] #{wall}  #{done}/#{@total_examples} examples  #{pct}  (#{completed}/#{total_workers} workers done)"
          $stdout.flush
        end
      end

      run_pool(pending, results) { |event, _worker, _result| completed += 1 if event == :done }
    ensure
      active = false
      ticker&.join
      @display.print_worker_summary(results)
    end

    # Shared scheduling loop: keep every free slot busy, reap finished workers,
    # recycle their slot, record the result, and yield lifecycle events.
    def run_pool(pending, results)
      in_flight = {}
      free_slots = @slots.dup

      loop do
        while !free_slots.empty? && !pending.empty?
          label, units = pending.pop
          slot = free_slots.shift
          worker = Worker.spawn(label: label, units: units, slot: slot, rspec_options: @rspec_options)
          in_flight[worker.pid] = worker
          yield(:started, worker)
        end

        break if in_flight.empty?

        pid, status = Process.wait2
        next unless (worker = in_flight.delete(pid))

        free_slots.push(worker.slot)
        result = {label: worker.label, units: worker.units, status: status.success? ? "PASS" : "FAIL", duration: worker.duration}
        results << result
        yield(:done, worker, result)
      end
    end

    def live_state
      @labels.each_with_index.to_h do |label, i|
        [label, {label: label, status: :pending, units: @planner.batches[i], started: nil, duration: nil, result: nil}]
      end
    end

    def repaint(live, frame, n, done)
      print "\e[#{n + 2}A"
      @labels.each { |label| print "\e[2K#{@display.spinner_line(live[label], frame)}\n" }
      print "\e[2K\n"
      print "\e[2K#{progress_bar(done, @total_examples)}\n"
    end

    def cleanup_progress
      @slots.each do |slot|
        File.delete(Config.progress_path(slot))
      rescue
        nil
      end
    end

    def elapsed_since(start_time) = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time).round

    def read_progress(file)
      return 0 unless file && File.exist?(file)

      Integer(File.read(file).strip)
    rescue
      0
    end

    def progress_bar(done, total, width: 36)
      return "" if total.zero?

      pct = (done.to_f / total * 100).round
      filled = (done.to_f / total * width).round
      bar = "\e[37m#{"▓" * filled}\e[90m#{"░" * (width - filled)}\e[0m"

      "  #{bar}  \e[36m#{done}/#{total}\e[0m  \e[1m#{pct}%\e[0m"
    end
  end
end
