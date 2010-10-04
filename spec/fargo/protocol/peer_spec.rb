require 'spec_helper'

describe Fargo::Protocol::Peer do

  let(:client) { Fargo::Client.new }

  let(:conn) {
    helper_object(described_class).tap do |conn|
      conn.stub :set_comm_inactivity_timeout
      conn.post_init
      conn.client = client
    end
  }

  include Fargo::Utils

  describe "the client to client handshake" do
    before :each do
      client.config.nick = 'fargo'
    end

    it "responds with all the correct info when the remote nick is received" do
      conn.should_receive(:send_data).with('$MyNick fargo|').ordered
      conn.should_receive(:send_data).with(/^\$Lock \w+ Pk=\w+\|$/).ordered
      conn.should_receive(:send_data).with(/^\$Supports (\w+ ?)+\|$/).ordered
      conn.should_receive(:send_data).with(
        /^\$Direction (Download|Upload) \d+\|$/).ordered
      conn.should_receive(:send_data).with(
        "$Key #{generate_key('lock')}|").ordered

      conn.receive_data '$MyNick foobar|$Lock lock Pk=pk|'
    end
  end

end
