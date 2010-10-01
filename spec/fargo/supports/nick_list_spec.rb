require 'spec_helper'

describe Fargo::Supports::NickList, :type => :em do

  before :each do
    @client = Fargo::Client.new
  end

  it 'gets the most up to date information about the nick' do
    @client.should_receive(:info).with('nick').twice
    @client.nick_has_slot? 'nick' # Triggers info the first time
    @client.nick_has_slot? 'nick' # Make sure we didn't cache the results
  end

  it "uses results from search queries for open slot information" do
    @client.channel.push [:search_result, {:nick => 'nick', :open_slots => 0}]
    @client.nick_has_slot?('nick').should be_false

    @client.channel.push [:search_result, {:nick => 'nick', :open_slots => 1}]
    @client.nick_has_slot?('nick').should be_true

    t = Time.now + 20.minutes
    Time.stub(:now).and_return t
    @client.stub(:info).with('nick').and_return nil
    @client.nick_has_slot?('nick').should be_false
  end
end
