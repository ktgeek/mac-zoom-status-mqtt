# frozen_string_literal: true

require "zoom_activity_publisher"
require "sys/proctable"

class LegacyZoomDetection
  ZOOM_PROCESS = /CptHost$/

  def initialize(options)
    @options = options
  end

  def meeting_active?
    processes = Sys::ProcTable.ps(thread_info: false)

    processes.any? { |p| p.exe =~ ZOOM_PROCESS }
  end

  def run
    publisher = ZoomActivityPublisher.new(name: ENV.fetch("DEVICE_NAME", nil), zoom_active: meeting_active?)

    loop do
      publisher.status = meeting_active?

      sleep @options[:poll_seconds]
    end
  end
end
