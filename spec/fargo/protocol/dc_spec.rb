require 'spec_helper'

describe Fargo::Protocol::DC do
  let(:conn) { helper_object described_class }

  before :each do
    conn.post_init
  end

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

  it "passes all binary data to :receive_data_chunk when necessary" do
    conn.should_receive(:receive_message).with(:hello,
      :type => :hello, :nick => 'fargo'){ |*args|
      conn.stub(:parse_data?).and_return false
      conn.should_receive(:receive_data_chunk).with('asdf')
    }

    conn.receive_data '$Hello fargo|'
    conn.receive_data 'asdf'
  end
end
