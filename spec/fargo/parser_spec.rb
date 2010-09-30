require 'spec_helper'

describe Fargo::Parser do

  let(:helper) {
    o = Object.new
    o.send(:class_eval) do
      include Fargo::Parser
    end
    o
  }

  it "correctly parses info strings" do
    helper.parse_message(
      "$MyINFO $ALL notdan <++ V:0.75,M:A,H:1/0/0,S:1,Dt:1.2.6/W>$ $Morewood A-D\001$$90932631814$"
    ).should == {
      :type      => :myinfo,
      :nick      => 'notdan',
      :speed     => 'Morewood A-D',
      :email     => '',
      :sharesize => 90932631814,
      :interest  => '<++ V:0.75,M:A,H:1/0/0,S:1,Dt:1.2.6/W>'
    }
  end

  it "correctly parses hello commands" do
    helper.parse_message("$Hello notdan").should == {
      :type => :hello,
      :nick => 'notdan'
    }
  end

  it "correctly parses the quit command" do
    helper.parse_message("$Quit ghostafaria").should == {
      :type => :quit,
      :nick => 'ghostafaria'
    }
  end

  it "correctly parses search commands" do
    helper.parse_message(
      "$Search 128.237.66.53:36565 F?T?0?1?west$wing").should == {
      :type => :search
    }
  end
end
