# frozen_string_literal: true

require "zoom_activity_publisher"

class MacOSLogStreamDetection
  # rubocop:disable Layout/LineLength
  MACOS_COMMAND = %{/usr/bin/log stream --predicate '(eventMessage CONTAINS "<<<< AVCaptureSession >>>> -[AVCaptureSession_Tundra startRunning]" || eventMessage CONTAINS "<<<< AVCaptureSession >>>> -[AVCaptureSession_Tundra stopRunning]")'}
  SESSION_RE = /(?<pid>\d+)\s+\d+\s+(?<command>[\w\.\-\(\))]+(?<_>\s[\w\.\-\(\))]+)*): \(AVFCapture\) \[[\w\.]+:\] <<<< AVCaptureSession >>>> -\[AVCaptureSession_Tundra (?<status>start|stop)Running\]/
  # rubocop:enable Layout/LineLength

  attr_reader :publisher, :logger, :capturers

  def initialize(publisher:, logger:)
    @publisher = publisher
    @logger = logger
    @capturers = Set.new
  end

  def run
    IO.popen(MACOS_COMMAND) do |io|
      io.readline # skip the header line from the command
      io.each_line do |line|
        md = line.match(SESSION_RE)
        next unless md

        pid = md[:pid].to_i

        case md[:status]
        when "start"
          logger.debug { "start for #{pid} #{md[:command]}" }
          capturers << pid
        when "stop"
          logger.debug { "stop for #{pid} #{md[:command]}" }
          capturers.delete(pid)
        else
          logger.error { "No action! Couldn't interpret: #{line}" }
        end

        logger.debug { "capturers: #{capturers.to_a}" }

        publisher.status = !capturers.empty?
      end
    end
  end
end
