require 'spec_helper'

describe Fargo::Protocol::PeerDownload, :type => :emsync do
  let(:conn) {
    helper_object(Fargo::Protocol::Peer).tap do |conn|
      conn.client     = Fargo::Client.new
      conn.instance_variable_set '@other_nick', 'foobar'
    end
  }

  shared_examples_for 'a downloader' do |command, data|
    it "downloads a file correctly after receiving: #{command}" do
      conn.stub(:send_message)

      conn.begin_download!
      conn.receive_data command
      conn.receive_data data

      file = conn.client.config.download_dir + '/foobar/file'
      file.should have_contents('0123456789')
    end
  end

  before :each do
    conn.stub :set_comm_inactivity_timeout
    conn.post_init
    conn.download = Fargo::Download.new 'foobar', 'path/to/file', 'tth', 100, 0

    Fargo::Throttler.stub(:new).and_return mock(:start_throttling => true,
                                                :stop_throttling => true,
                                                :throttle => true)
  end

  describe 'the standard DC protocol for downloading' do
    before :each do
      conn.instance_variable_set '@peer_extensions', []
    end

    it "requests a download via the $Get command" do
      conn.should_receive(:send_message).with('Get', "path/to/file$1")

      conn.begin_download!
    end

    it "requests the file to be sent after the $FileLength command" do
      conn.stub(:send_message).with('Get', "path/to/file$1")
      conn.should_receive(:send_message).with('Send')

      conn.begin_download!
      conn.receive_data '$FileLength 10|'
    end

    it_should_behave_like 'a downloader', '$FileLength 10|', '0123456789'
  end

  describe 'the ADC protocol for downloading' do
    before :each do
      conn.instance_variable_set '@peer_extensions', ['ADCGet']
    end

    context "with zlib compression" do
      before :each do
        conn.instance_variable_get('@peer_extensions') << 'ZLIG'
      end

      it "requests a download via the $ADCGET command with ZL1" do
        conn.should_receive(:send_message).with('ADCGET',
          'file path/to/file 0 100 ZL1')

        conn.begin_download!
      end

      it_should_behave_like 'a downloader',
        '$ADCSND file path/to/file 0 10 ZL1|',
        Zlib::Deflate.deflate('0123456789')

      it_should_behave_like 'a downloader',
        '$ADCSND file path/to/file 0 10|', '0123456789'
    end

    context "without zlib compression" do
      it "requests a download via the $ADCGET command with ZL1" do
        conn.should_receive(:send_message).with('ADCGET',
          'file path/to/file 0 100')

        conn.begin_download!
      end

      it_should_behave_like 'a downloader',
        '$ADCSND file path/to/file 0 10|', '0123456789'
    end

    context "with TTHF enabled" do
      before :each do
        conn.instance_variable_get('@peer_extensions') << 'TTHF'
      end

      it "requests a download via $ADCGET with the tth of the file" do
        conn.should_receive(:send_message).with('ADCGET', 'file TTH/tth 0 100')

        conn.begin_download!
      end

      it_should_behave_like 'a downloader',
        '$ADCSND file TTH/tth 0 10|', '0123456789'
    end
  end
end
