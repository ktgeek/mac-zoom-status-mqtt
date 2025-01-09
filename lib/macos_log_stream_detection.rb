# frozen_string_literal: true

require "zoom_activity_publisher"

class MacOSLogStreamDetection
  MACOS_COMMAND = %{/usr/bin/log stream --predicate '(eventMessage CONTAINS "<<<< AVCaptureSession >>>> -[AVCaptureSession_Tundra startRunning]" || eventMessage CONTAINS "<<<< AVCaptureSession >>>> -[AVCaptureSession_Tundra stopRunning]")'} # rubocop:disable Layout/LineLength
  SESSION_RE = /-\[AVCaptureSession_Tundra (start|stop)Running\]/

  def initialize(logger:)
    @logger = logger
  end

  def run
    publisher = ZoomActivityPublisher.new(name: ENV.fetch("DEVICE_NAME", nil))

    IO.popen(MACOS_COMMAND) do |io|
      io.readline # skip the header line from the command
      io.each_line do |line|
        md = line.match(SESSION_RE)
        next unless md

        status = case md[1]
                 when "start"
                   @logger.debug { "starting" }
                   true
                 when "stop"
                   @logger.debug { "stopping" }
                   false
                 else
                   @logger.error { "No action! Couldn't interpret: #{line}" }
                   nil
                 end
        publisher.status = status unless status.nil?
      end
    end
  end
end
