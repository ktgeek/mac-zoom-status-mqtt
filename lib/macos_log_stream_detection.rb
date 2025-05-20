# frozen_string_literal: true

require 'forwardable'
require "zoom_activity_publisher"
require 'concurrent/scheduled_task'

class MacOSLogStreamDetection
  # The stream command is only catching the camera, not mic. I still haven't figure out a sane/simple way to detect mic only usage.
  # TODO: figure out mic only usage
  # rubocop:disable Layout/LineLength
  MACOS_COMMAND = %{/usr/bin/log stream --predicate '(eventMessage CONTAINS "<<<< AVCaptureSession >>>> -[AVCaptureSession_Tundra startRunning]" || eventMessage CONTAINS "<<<< AVCaptureSession >>>> -[AVCaptureSession_Tundra stopRunning]")'}
  SESSION_RE = /(?<pid>\d+)\s+\d+\s+(?<command>[\w\.\-\(\))]+(?<_>\s[\w\.\-\(\))]+)*): \(AVFCapture\) \[[\w\.]+:\] <<<< AVCaptureSession >>>> -\[AVCaptureSession_Tundra (?<status>start|stop)Running\]/
  # rubocop:enable Layout/LineLength

  attr_reader :publisher, :logger, :capturers

  # sometimes the same app/pid can open the camera stream multiple times, so use this counter to track them.
  # TODO: if this approach works better, move this into its own file
  class PidCounter
    extend Forwardable

    def_delegators :@pids, :empty?, :to_s, :any?

    def initialize
      @pids = Hash.new { |h, k| h[k] = 0 }
    end

    def add(pid)
      @pids[pid] += 1
    end

    def remove(pid)
      @pids[pid] -= 1
      @pids.delete(pid) if @pids[pid] <= 0
    end
  end

  def initialize(publisher:, logger:)
    @publisher = publisher
    @logger = logger
    @capturers = PidCounter.new
  end

  def run
    task = nil
    IO.popen(MACOS_COMMAND) do |io|
      io.readline # skip the header line from the command
      io.each_line do |line|
        md = line.match(SESSION_RE)
        next unless md

        pid = md[:pid].to_i

        case md[:status]
        when "start"
          logger.debug { "start for #{pid} #{md[:command]}" }
          capturers.add(pid)
        when "stop"
          logger.debug { "stop for #{pid} #{md[:command]}" }
          capturers.remove(pid)
        else
          logger.error { "No action! Couldn't interpret: #{line}" }
        end

        logger.debug { "capturers: #{capturers} should_be_on: #{capturers.any?}" }

        # Probably an overly complicated way to debounce
        unless task&.pending?
          logger.debug { "Scheduling task to set status" }
          task = Concurrent::ScheduledTask.new(1) do
            should_be_on = capturers.any?
            publisher.status = should_be_on if publisher.status != should_be_on
            logger.debug { "Setting status to #{should_be_on}" }
          end
          task.execute
        else
          logger.debug { "Task already scheduled, not scheduling again" }
        end
      end
    end
  end
end
