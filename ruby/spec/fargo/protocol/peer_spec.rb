require 'spec_helper'

describe Fargo::Protocol::Peer do

  let(:client) { Fargo::Client.new }

  let(:conn) {
    helper_object(described_class).tap do |conn|
      conn.stub(:generate_lock).and_return ['lock', 'pk']
      conn.stub :set_comm_inactivity_timeout
      conn.post_init
      conn.client = client
    end
  }

  include Fargo::Utils

  describe "the client to client handshake", :type => :emsync do
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

    it "responds correctly when the nick is sent first" do
      conn.should_receive(:send_data).with('$MyNick fargo|').ordered
      conn.should_receive(:send_data).with('$Lock lock Pk=pk|').ordered

      conn.send_lock

      conn.should_receive(:send_data).with(/^\$Supports (\w+ ?)+\|$/).ordered
      conn.should_receive(:send_data).with(
        /^\$Direction (Download|Upload) \d+\|$/).ordered
      conn.should_receive(:send_data).with(
        "$Key #{generate_key('lock')}|").ordered

      conn.receive_data '$MyNick foobar|$Lock lock Pk=pk|$Supports a|' +
        "$Direction Download 100|$Key #{generate_key('lock')}|"
    end

    context "out of order handshakes" do
      it "doesn't like a lock before MyNick" do
        conn.should_receive(:close_connection)
        conn.receive_data '$Lock lock Pk=pk|'
      end

      it "doesn't like MyNick twice'" do
        conn.should_receive(:close_connection)
        conn.receive_data '$MyNick foobar|$MyNick asdf|'
      end

      it "doesn't like Supports before MyNick'" do
        conn.should_receive(:close_connection)
        conn.receive_data '$Supports asdf|'
      end

      it "doesn't like Direction up front'" do
        conn.should_receive(:close_connection)
        conn.receive_data '$Direction Download 3|'
      end

      it "doesn't like Key up front'" do
        conn.should_receive(:close_connection)
        conn.receive_data '$Key foo|'
      end
    end
  end

  it "disconnects with an appropriate message" do
    client.channel.should_receive(:<<).with(
      [:peer_disconnected, instance_of(Hash)])

    conn.unbind
  end
end
