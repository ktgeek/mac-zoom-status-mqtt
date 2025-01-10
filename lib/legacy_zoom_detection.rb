# frozen_string_literal: true

require "zoom_activity_publisher"
require "sys/proctable"

class LegacyZoomDetection
  attr_reader :publisher

  ZOOM_PROCESS = /CptHost$/

  def initialize(publisher:, options:)
    @publisher = publisher
    @options = options
  end

  def meeting_active?
    processes = Sys::ProcTable.ps(thread_info: false)

    processes.any? { |p| p.exe =~ ZOOM_PROCESS }
  end

  def run
    loop do
      publisher.status = meeting_active?

      sleep @options[:poll_seconds]
    end
  end
end
