require 'spec_helper'

describe Fargo::Protocol::Hub do
  let(:conn) { helper_object described_class }
  include Fargo::TTH

  context "searches" do
    let(:file1) { Fargo.config.download_dir + '/file12' }
    let(:file2) { Fargo.config.download_dir + '/file23' }
    let(:file3) { Fargo.config.download_dir + '/file34' }

    before :each do
      File.open(file1, 'w'){ |f| f << 'garbage' }
      File.open(file2, 'w'){ |f| f << 'garbage' }
      File.open(file3, 'w'){ |f| f << 'garbage' }
      conn.client = Fargo::Client.new
      conn.client.stub(:nicks).and_return ['foobar']
      conn.client.share_directory Fargo.config.download_dir
      conn.post_init
    end

    it "searches results and sends the results to the hub" do
      conn.should_receive(:send_message).with('SR',
        "fargo tmp\\file12\0057 4/4\005TTH:#{file_tth file1} " +
        "(127.0.0.1:7314)\005foobar")

      query = Fargo::Search.new :query => 'file1'
      conn.receive_data "$Search Hub:foobar #{query}|"
    end

    it "sends all hits to the hub" do
      conn.should_receive(:send_message).with('SR',
        "fargo tmp\\file23\0057 4/4\005TTH:#{file_tth file2} " +
        "(127.0.0.1:7314)\005foobar")

      conn.should_receive(:send_message).with('SR',
        "fargo tmp\\file34\0057 4/4\005TTH:#{file_tth file3} " +
        "(127.0.0.1:7314)\005foobar")

      query = Fargo::Search.new :query => '3'
      conn.receive_data "$Search Hub:foobar #{query}|"
    end

    it "sends active hits via EventMachine" do
      stub = double 'connection'
      stub.should_receive(:send_datagram).with('$SR ' +
        "fargo tmp\\file12\0057 4/4\005TTH:#{file_tth file1} " +
        "(127.0.0.1:7314)|", '127.0.0.1', 7000).ordered
      stub.should_receive(:close_connection_after_writing).ordered

      EventMachine.stub(:open_datagram_socket).with('0.0.0.0', 0).
        and_return stub

      query = Fargo::Search.new :query => 'file1'
      conn.receive_data "$Search 127.0.0.1:7000 #{query}|"
    end
  end
end
