# frozen_string_literal: true

require 'spec_helper'

describe 'Live testing' do
  before do
    skip('No live testing') unless ENV['LIVE']
  end

  context 'with a real UDP socket' do
    it 'should actually send stuff over the socket' do
      socket = UDPSocket.new
      host, port = 'localhost', 12345
      socket.bind(host, port)

      statsd = Datadog::Statsd.new(host, port)
      statsd.increment('foobar')
      message = socket.recvfrom(64).first
      expect(message).to eq 'foobar:1|c'
    end
  end
end
