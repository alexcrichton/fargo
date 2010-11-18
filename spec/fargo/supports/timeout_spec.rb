require 'spec_helper'

describe Fargo::Supports::Timeout do
  let(:client) { Fargo::Client.new }

  it "calls sleep with the specified timeout interval" do
    client.should_receive(:sleep).with 10

    client.timeout_response(10, lambda{ true })
  end

  it "yields to the given block before sleep is called" do
    client.stub(:sleep).and_raise(Exception.new("Shouldn't be called!"))

    client.timeout_response(10, lambda{ true }) do
      client.stub(:sleep)
    end
  end

  describe "with the EM reactor running", :type => :em_different_thread do
    let(:mock_block) { mock('block', :call => true) }

    it "calls the given block with the arguments sent to the channel" do
      mock_block.should_receive(:call).with('a')

      client.timeout_response(0, mock_block) do
        client.channel << 'a'
      end
    end

    it "actually times out correctly" do
      Thread.start{ sleep 0.05; client.channel << 'foobar' }

      t = Time.now
      client.timeout_response(1, mock_block)
      (Time.now - t).should be_within(0.01).of(0.05)
    end

  end
end
