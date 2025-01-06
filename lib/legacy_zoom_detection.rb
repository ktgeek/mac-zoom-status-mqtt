# frozen_string_literal: true

require "zoom_activity_publisher"
require "sys/proctable"

class LegacyZoomDetection
  ZOOM_PROCESS = /CptHost$/.freeze
  # Slack doesn't seem to start a help in process for just audio... well, they do, but its started shortly after slack
  # starts.. so this will detect if video capture is running, so we'll assume that's a meeting, especially since I'm a
  # camera on kind of guy.
  SLACK_PROCESS = /Slack Helper \(Plugin\)$/.freeze
  SLACK_ARG = /utility-sub-type=video_capture.mojom.VideoCaptureService/.freeze

  def initialize(options)
    @options = options
  end

  def meeting_active?
    processes = Sys::ProcTable.ps(thread_info: false)

    # processes.any? { |p| p.exe =~ ZOOM_PROCESS || (p.exe =~ SLACK_PROCESS && p.cmdline =~ SLACK_ARG) }
    processes.any? { |p| p.exe =~ ZOOM_PROCESS }
  end

  def run
    publisher = ZoomActivityPublisher.new(name: ENV["DEVICE_NAME"], zoom_active: meeting_active?)

    loop do
      publisher.status = meeting_active?

      sleep @options[:poll_seconds]
    end
  end
end
