require 'spec_helper'

describe Fargo::Supports::NickList, :type => :em do

  before :each do
    @client = Fargo::Client.new
    @client.stub(:get_info)
  end

  it 'gets the most up to date information about the nick' do
    @client.should_receive(:info).with('nick').twice
    @client.nick_has_slot?('nick') { |_| }
    @client.nick_has_slot?('nick') { |_| }
  end

  it "uses results from search queries for open slot information" do
    @client.channel << [:search_result, {:nick => 'nick', :open_slots => 0}]
    @client.nick_has_slot?('nick') do |value|
      value.should be_false
    end

    @client.channel << [:search_result, {:nick => 'nick', :open_slots => 1}]
    @client.nick_has_slot?('nick') do |value|
      value.should be_true
    end

    t = Time.now + 20.minutes
    Time.stub(:now).and_return t
    @client.stub(:info).with('nick').and_return nil
    @client.nick_has_slot?('nick') do |value|
      value.should be_false
    end
  end

  it "gets the nick list from the subscribed channel" do
    @client.nicks.should == []

    @client.channel << [:nick_list, {:nicks => ['a', 'b']}]

    @client.nicks.should == ['a', 'b']
  end
end
