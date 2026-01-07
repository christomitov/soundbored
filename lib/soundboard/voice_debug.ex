defmodule Soundboard.VoiceDebug do
  @moduledoc """
  Temporary debug module to log voice packet formats.
  Add this to understand what Discord is sending.
  """
  
  require Logger
  
  def log_packet(packet) when byte_size(packet) < 12 do
    Logger.warning("Short packet (#{byte_size(packet)} bytes): #{inspect(packet, limit: 50)}")
    :short
  end
  
  def log_packet(<<first_byte::8, second_byte::8, rest::binary>> = packet) do
    # Parse RTP/RTCP header
    version = first_byte >>> 6
    padding = (first_byte >>> 5) &&& 1
    extension = (first_byte >>> 4) &&& 1
    csrc_count = first_byte &&& 0x0F
    marker = second_byte >>> 7
    payload_type = second_byte &&& 0x7F
    
    Logger.warning("""
    Packet (#{byte_size(packet)} bytes):
      Version: #{version}, Padding: #{padding}, Extension: #{extension}
      CSRC count: #{csrc_count}, Marker: #{marker}, PT: #{payload_type}
      First bytes: #{inspect(:binary.part(packet, 0, min(20, byte_size(packet))), limit: 50)}
    """)
    
    {:ok, payload_type}
  end
end
