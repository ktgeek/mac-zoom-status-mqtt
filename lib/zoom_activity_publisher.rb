# frozen_string_literal: true

require "homie-mqtt"
require "socket"

class ZoomActivityPublisher
  def initialize(name: nil, mqtt: ENV.fetch("MQTT_URL", nil), zoom_active: false)
    hostname = name || Socket.gethostname
    short_name = name || MQTT::Homie.escape_id(hostname.split(".")[0])
    @device = MQTT::Homie::Device.new(short_name, hostname, mqtt: mqtt, clear_topics: false)
    @device.node("zoom-activity", "Zoom Activity", "status") do |node|
      node.property("status", "status", :boolean, zoom_active)
    end
    @device.publish
  end

  def status=(state)
    @device["zoom-activity"]["status"].value = state
  end
end
