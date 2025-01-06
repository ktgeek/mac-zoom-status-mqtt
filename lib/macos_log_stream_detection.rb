# frozen_string_literal: true

require "zoom_activity_publisher"

class MacOSLogStreamDetection
  MACOS_COMMAND = %{/usr/bin/log stream --predicate '(eventMessage CONTAINS "<<<< AVCaptureSession >>>> -[AVCaptureSession_Tundra startRunning]" || eventMessage CONTAINS "<<<< AVCaptureSession >>>> -[AVCaptureSession_Tundra stopRunning]")'}
  SESSION_RE = /-\[AVCaptureSession_Tundra (start|stop)Running\]/

  def run
    publisher = ZoomActivityPublisher.new(name: ENV.fetch("DEVICE_NAME", nil))

    IO.popen(MACOS_COMMAND) do |io|
      io.readline # skip the header line from the command
      io.each_line do |line|
        md = line.match(SESSION_RE)
        next unless md

        status = case md[1]
                 when "start" then true
                 when "stop" then false
                 end
        publisher.status = status
      end
    end
  end
end
