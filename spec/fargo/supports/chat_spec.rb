require 'spec_helper'

describe Fargo::Supports::Chat, :type => :em do
  let(:client) { Fargo::Client.new }

  it "keeps a log of all messages sent" do
    client.channel << [:chat, 'this is a chat!']
    client.messages.should == ['this is a chat!']

    client.channel << [:chat, 'another chat']
    client.messages.should == ['this is a chat!', 'another chat']
  end

  it "keeps a log of all private messages sent" do
    client.channel << [:privmsg, {:from => 'foo', :msg => 'this is a chat!'}]
    client.channel << [:privmsg, {:from => 'foo', :msg => 'another'}]

    client.messages_with('foo').should == [
      {:from => 'foo', :msg => 'this is a chat!'},
      {:from => 'foo', :msg => 'another'}
    ]
  end

  it "clears all the messages once the hub disconnects" do
    client.channel << [:chat, 'this is a chat!']
    client.channel << [:privmsg, {:from => 'foo', :msg => 'this is a chat!'}]

    client.channel << [:hub_disconnected, 'foobar!']

    client.messages.should == []
    client.messages_with('foo').should == []
  end
end
