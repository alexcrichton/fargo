require 'spec_helper'

describe Fargo::Supports::Timeout do
  let(:client) { Fargo::Client.new }
  let!(:mock_counter) { Fargo::BlockingCounter.new 1 }

  before :each do
    Fargo::BlockingCounter.stub(:new).and_return mock_counter
  end

  it "calls sleep with the specified timeout interval" do
    mock_counter.should_receive(:wait).with(10)

    client.timeout_response(10, lambda{ true })
  end

  it "yields to the given block before sleep is called" do
    mock_counter.stub(:wait).and_raise(Exception.new("Shouldn't be called!"))

    client.timeout_response(10, lambda{ true }) do
      mock_counter.stub(:wait)
    end
  end

  describe "with the EM reactor running", :type => :em_different_thread do
    let(:mock_block) { mock('block', :call => true) }

    it "calls the given block with the arguments sent to the channel" do
      mock_block.should_receive(:call).with('a').and_return true

      client.timeout_response(10, mock_block) do
        client.channel << 'a'
      end
    end

  end
end
