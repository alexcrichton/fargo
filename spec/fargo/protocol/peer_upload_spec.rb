require 'spec_helper'

describe Fargo::Protocol::PeerUpload do
  let(:conn) {
    helper_object(Fargo::Protocol::Peer).tap do |conn|
      conn.client     = Fargo::Client.new
    end
  }
  let(:file) { Fargo.config.download_dir + '/file' }

  before :each do
    File.open(file, 'w'){ |f| f << '0123456789' }
    conn.client.share_directory Fargo.config.download_dir
    conn.stub(:set_comm_inactivity_timeout)
    conn.stub(:get_outbound_data_size).and_return 0
    conn.post_init
    conn.instance_variable_set '@handshake_step', 5
  end

  describe "the standard DC protocol using $Get" do
    it "sends the $FileLength command with the length of the file requested" do
      conn.should_receive(:send_message).with('FileLength', 10)

      conn.receive_data '$Get tmp/file$1|'
    end

    it "uploads the file after receiving $Send" do
      conn.stub(:send_message)
      conn.receive_data '$Get tmp/file$1|'
      conn.should_receive(:send_data).with('0123456789')
      conn.receive_data '$Send|'
    end
  end

  describe "uploading via the ADC protocol" do
    it "sends the $ADCSND command with ZL1 if requested" do
      conn.should_receive(:send_message).with('ADCSND',
        'file tmp/file 0 10 ZL1')
      conn.stub(:begin_streaming)

      conn.receive_data '$ADCGET file tmp/file 0 -1 ZL1|'
    end

    it "sends the $ADCSND command without ZL1 when not requested" do
      conn.should_receive(:send_message).with('ADCSND', 'file tmp/file 0 10')
      conn.stub(:begin_streaming)

      conn.receive_data '$ADCGET file tmp/file 0 -1|'
    end

    it "immediately begins uploading the file" do
      conn.stub(:send_message)
      conn.should_receive(:send_data).with '0123'

      conn.receive_data '$ADCGET file tmp/file 0 4|'
    end

    it "compresses the sent data with zlib if requested" do
      conn.stub(:send_message)
      conn.should_receive(:send_data).with Zlib::Deflate.deflate('0123')

      conn.receive_data '$ADCGET file tmp/file 0 4 ZL1|'
    end
  end

  describe "huge files" do
    let(:size) { 16 * 1024 * 2 + 100 }

    before :each do
      File.open(file + '2', 'w'){ |f| f << ('a' * size) }
      conn.client.share_directory Fargo.config.download_dir
    end

    it "are uploaded efficiently" do
      conn.stub(:send_message)
      conn.should_receive(:send_data).with('a' * 16 * 1024).twice.ordered
      conn.should_receive(:send_data).with('a' * 100).ordered

      conn.receive_data '$ADCGET file tmp/file2 0 -1|'
    end

    it "compresses successfully" do
      sent_data = ''
      conn.stub(:send_message)
      conn.stub(:send_data){ |d| sent_data << d }

      conn.receive_data '$ADCGET file tmp/file2 0 -1 ZL1|'
      sent_data.should == Zlib::Deflate.deflate('a' * size)
    end
  end

  it "sends $MaxedOut when the client has no slots" do
    conn.client.take_slot! while conn.client.open_upload_slots > 0

    conn.should_receive(:send_message).with('MaxedOut')

    conn.receive_data '$Get tmp/file$1|'
  end

  it "doesn't sent $MaxedOut if the requested file is the file list" do
    conn.client.take_slot! while conn.client.open_upload_slots > 0

    conn.stub(:send_message)
    conn.should_receive(:send_message).with('MaxedOut').never
    conn.stub(:begin_streaming)

    conn.receive_data '$Get files.xml.bz2$1|'
  end

  it "sends $Error when the requested file does not exist" do
    conn.should_receive(:send_message).with('Error', 'File Not Available')

    conn.receive_data '$Get tmp/nonexistent$1|'
  end
end
