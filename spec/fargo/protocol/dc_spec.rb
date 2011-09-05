require 'spec_helper'

describe Fargo::Protocol::DC do
  let(:conn) { helper_object described_class }
  let(:client) { Fargo::Client.new }

  before :each do
    conn.post_init
    conn.client = client
  end

  context "receiving data" do
    it "parses the received data and passes it along to :receive_message" do
      conn.should_receive(:receive_message).with(:hello,
        :type => :hello, :nick => 'fargo')

      conn.receive_data '$Hello fargo|'
    end

    it "handles receiving two chunks of data at once" do
      conn.should_receive(:receive_message).with(:hello,
        :type => :hello, :nick => 'fargo').ordered
      conn.should_receive(:receive_message).with(:hello,
        :type => :hello, :nick => 'foobar').ordered

      conn.receive_data '$Hello fargo|$Hello foobar|'
    end

    it "handles receiving data in partial chunks" do
      conn.should_receive(:receive_message).with(:hello,
        :type => :hello, :nick => 'fargo').ordered
      conn.should_receive(:receive_message).with(:hello,
        :type => :hello, :nick => 'foobar').ordered

      conn.receive_data '$Hello far'
      conn.receive_data 'go|$Hello'
      conn.receive_data ' foobar|'
    end

    it "doesn't call unnecessary methods when the data hasn't been received" do
      conn.should_receive(:receive_message).with(:hello,
        :type => :hello, :nick => 'fargo').ordered

      conn.receive_data '$Hello fargo|$Hello fooba'
    end

    it "passes binary data back to :receive_binary_data" do
      conn.should_receive(:receive_message).with(:hello,
        :type => :hello, :nick => 'fargo'){ |*args|
        conn.instance_variable_set(:@parsing, false)
      }
      conn.should_receive(:receive_binary_data).with('asdf')

      conn.receive_data '$Hello fargo|'
      conn.receive_data 'asdf'
    end

    it "passes merged binary data back to :receive_data" do
      conn.should_receive(:receive_message).with(:hello,
        :type => :hello, :nick => 'fargo'){ |*args|
        conn.instance_variable_set(:@parsing, false)
        conn.should_receive(:receive_binary_data).with('asdf')
      }

      conn.receive_data '$Hello fargo|asdf'
    end
  end

  context "sending data" do
    it "appends a $ to all commands sent with a pipe at the end" do
      conn.should_receive(:send_data).with('$Foo|')
      conn.send_message 'Foo'
    end

    it "allows for arguments to be specified as well" do
      conn.should_receive(:send_data).with('$Foo bar baz|')
      conn.send_message 'Foo', 'bar baz'
    end
  end

  it "alerts the client when it's been disconnected" do
    conn.client = client
    client.channel.should_receive(:<<).with(
      [:dc_disconnected, instance_of(Hash)])

    conn.unbind
  end
end
