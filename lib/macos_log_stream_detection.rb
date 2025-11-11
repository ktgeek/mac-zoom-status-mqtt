# frozen_string_literal: true

require "English"
require "forwardable"
require "zoom_activity_publisher"
require "concurrent/scheduled_task"
require "json"

# logging data on camera and mic from https://github.com/objective-see/OverSight/blob/main/Application/Application/AVMonitor.m#L214

class MacOSLogStreamDetection
  # Yes, this is gross AF, but I couldn't think of a better way to get the command to be understandable and easily
  # editble
  def self.macos_command
    @macos_command ||= begin
      command = <<~FOO
        /usr/bin/log stream
          --predicate '(subsystem=="com.apple.cmio"
                        AND
                        (eventMessage CONTAINS "added <private> endpoint <private> camera <private>"
                        OR
                        eventMessage CONTAINS "removed endpoint <private>"))
                      OR
                      (subsystem=="com.apple.coremedia"
                        AND
                        (eventMessage CONTAINS "-[MXCoreSession beginInterruption]:"
                        OR
                        eventMessage CONTAINS "-[MXCoreSession endInterruption:]:"))'
          --style ndjson
      FOO
      command.tr("\n", " ").squeeze(" ")
    end
  end

  CAMARA_ON_RE = /added <private> endpoint <private> camera <private>/
  CAMARA_OFF_RE = /removed endpoint <private>/
  MIC_ON_RE = /-\[MXCoreSession beginInterruption\]: Session <ID: (?<id>\d+), PID = (?<pid>\d+),/
  MIC_OFF_RE = /-\[MXCoreSession endInterruption:\]: Session <ID: (?<id>\d+), PID = (?<pid>\d+),/

  attr_reader :publisher, :logger, :mic_capturers

  class PidCounter
    extend Forwardable

    def_delegators :@pids, :empty?, :to_s, :any?

    def initialize
      @pids = Hash.new { |h, k| h[k] = 0 }
    end

    def add(session, pid)
      @pids[[session, pid]] += 1
    end

    def remove(session, pid)
      key = [session, pid]
      @pids[key] -= 1
      @pids.delete(key) if @pids[key] <= 0
    end
  end

  def initialize(publisher:, logger:)
    @publisher = publisher
    @logger = logger
    @mic_capturers = PidCounter.new
  end

  def run
    task = nil
    camera_count = 0

    logger.debug { "Starting log stream with command: #{MacOSLogStreamDetection.macos_command}" }
    IO.popen(MacOSLogStreamDetection.macos_command) do |io|
      io.readline # skip the header line from the command
      io.each_line do |line|
        json = JSON.parse(line)

        event_message = json["eventMessage"]

        case json["subsystem"]
        when "com.apple.cmio"
          case event_message
          when CAMARA_ON_RE
            logger.debug { "camera ON detected" }
            camera_count += 1
          when CAMARA_OFF_RE
            logger.debug { "camera OFF detected" }
            camera_count -= 1 if camera_count > 0
          end
        when "com.apple.coremedia"
          case event_message
            # matchdata is in $~
          when MIC_ON_RE
            logger.debug { "mic ON detected" }
            mic_capturers.add($LAST_MATCH_INFO[:id], $LAST_MATCH_INFO[:pid])
          when MIC_OFF_RE
            logger.debug { "mic OFF detected" }
            mic_capturers.remove($LAST_MATCH_INFO[:id], $LAST_MATCH_INFO[:pid])
          end
        end

        logger.debug { "camera count: #{camera_count}, capturers: #{mic_capturers}" }

        # Probably an overly complicated way to debounce
        if task&.pending?
          logger.debug { "Task already scheduled, not scheduling again" }
        else
          logger.debug { "Scheduling task to set status" }
          task = Concurrent::ScheduledTask.new(1) do
            should_be_on = mic_capturers.any? || camera_count.positive?
            publisher.status = should_be_on if publisher.status != should_be_on
            logger.debug { "Setting status to #{should_be_on}" }
          end
          task.execute
        end
      end
    end
  end
end
