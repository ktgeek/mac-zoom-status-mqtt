# frozen_string_literal: true

require "zoom_activity_publisher"

class MacOSLogStreamDetection
  MACOS_COMMAND = %{/usr/bin/log stream --predicate '(eventMessage CONTAINS "<<<< AVCaptureSession >>>> -[AVCaptureSession_Tundra startRunning]" || eventMessage CONTAINS "<<<< AVCaptureSession >>>> -[AVCaptureSession_Tundra stopRunning]")'} # rubocop:disable Layout/LineLength
  SESSION_RE = /(?<pid>\d+)\s+\d+\s+(?<command>[\w\.\-]+(?<_>\s[\w\.\-]+)*): \(AVFCapture\) \[com.apple.cameracapture:\] <<<< AVCaptureSession >>>> -\[AVCaptureSession_Tundra (?<status>start|stop)Running\]/ # rubocop:disable Layout/LineLength

  def initialize(logger:)
    @logger = logger
    @capturers = Set.new
  end

  def run
    publisher = ZoomActivityPublisher.new(name: ENV.fetch("DEVICE_NAME", nil))

    IO.popen(MACOS_COMMAND) do |io|
      io.readline # skip the header line from the command
      io.each_line do |line|
        md = line.match(SESSION_RE)
        next unless md

        pid = md[:pid].to_i

        case md[:status]
        when "start"
          @logger.debug { "start for #{pid} #{md[:command]}" }
          @capturers << pid
        when "stop"
          @logger.debug { "stop for #{pid} #{md[:command]}" }
          @capturers.delete(pid)
        else
          @logger.error { "No action! Couldn't interpret: #{line}" }
        end

        @logger.debug { "capturers: #{@capturers.to_a}" }

        publisher.status = !@capturers.empty?
      end
    end
  end
end
