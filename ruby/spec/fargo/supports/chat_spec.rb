require 'spec_helper'

describe Fargo::Supports::Chat, :type => :emsync do
  let(:client) { Fargo::Client.new }
  let(:chat) { {:from => 'foo', :text => 'this is a chat!'} }
  let(:chat2) { {:from => 'bar', :text => 'another'} }

  it "keeps a log of all messages sent" do
    client.channel << [:chat, chat]
    client.messages.should == [chat]

    client.channel << [:chat, chat2]
    client.messages.should == [chat, chat2]
  end

  it "keeps a log of all private messages sent" do
    client.channel << [:privmsg, chat]
    chat2[:from] = chat[:from]
    client.channel << [:privmsg, chat2]

    client.messages_with('foo').should == [chat, chat2]
  end

  it "clears all the messages once the hub disconnects" do
    client.channel << [:chat, chat]
    client.channel << [:privmsg, chat]
    client.channel << [:hub_disconnected, {}]

    client.messages.should == []
    client.messages_with('foo').should == []
  end

  it "sends the correct message when chatting" do
    # TODO: don't call ugly instance_variable_set
    client.instance_variable_set('@hub', hub = mock)
    hub.should_receive(:send_data).with('<fargo> hello world!|')

    client.send_chat 'hello world!'
  end

  it "clears excessive chat messages with a periodic timer" do
    EventMachine.should_receive(:add_periodic_timer).with(60).and_yield

    200.times{
      client.channel << [:chat, chat2]
      client.channel << [:privmsg, chat]
    }
    client.send(:periodically_remove_chats)
    client.messages.should == Array.new(100, chat2)
    client.messages_with('foo').should == Array.new(100, chat)
  end
end
