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
  COMMAND = <<~FOO.tr("\n", " ").squeeze(" ").freeze
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

  CAMARA_ON_RE = /added <private> endpoint <private> camera <private>/
  CAMARA_OFF_RE = /removed endpoint <private>/
  MIC_RE = /-\[MXCoreSession (?<event>begin|end)Interruption:?\]: Session <ID: (?<id>\d+), PID = (?<pid>\d+), Name = \S+, (?<name>[\S+ ]+)\(\d+\),/ # rubocop:disable Layout/LineLength

  # These are processes that are known to trigger mic access on my system that I want to ignore. If others are using
  # this and need/want to add to it, maybe we'll make this configurable. But for now, hard code city, baby!
  MIC_EXCEPTIONS = ["arkaudiod", "systemsoundserve", "loginwindow", "corespeechd", "iPhone Mirroring"].to_set.freeze

  attr_reader :publisher, :logger, :mic_capturers
  attr_accessor :camera_count

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
    @camera_count = 0
  end

  def handle_camera(event_message)
    case event_message
    when CAMARA_ON_RE
      logger.debug { "camera ON detected" }
      self.camera_count += 1
    when CAMARA_OFF_RE
      logger.debug { "camera OFF detected" }
      self.camera_count -= 1 if camera_count.positive?
    end
  end

  def handle_mic(event_message)
    md = event_message.match(MIC_RE)
    return unless md

    ignore = MIC_EXCEPTIONS.include?(md[:name])
    logger.debug { "mic #{md[:event]} detected for #{md[:name]}#{' (ignored)' if ignore}" }
    mic_capturers.public_send((md[:event] == "begin" ? :add : :remove), md[:id], md[:pid]) unless ignore
  end

  def run
    task = nil

    logger.debug { "Starting log stream with command: #{COMMAND}" }
    IO.popen(COMMAND) do |io|
      io.readline # skip the header line from the command
      io.each_line do |line|
        json = JSON.parse(line)

        event_message = json["eventMessage"]
        case json["subsystem"]
        when "com.apple.cmio"
          handle_camera(event_message)
        when "com.apple.coremedia"
          handle_mic(event_message)
        end

        logger.debug { "camera count: #{camera_count}, capturers: #{mic_capturers}" }

        # Probably an overly complicated way to debounce
        if task&.pending?
          logger.debug { "Task already scheduled, not scheduling again" }
        else
          logger.debug { "Scheduling task to set status" }
          task = Concurrent::ScheduledTask.new(1) do
            should_be_on = mic_capturers.any? || camera_count.positive?
            if publisher.status != should_be_on
              publisher.status = should_be_on
              logger.debug { "Setting status to #{should_be_on}" }
            end
          end
          task.execute
        end
      end
    end
  end
end
