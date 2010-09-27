require 'spec_helper'

describe Fargo::Utils do

  let(:helper) {
    o = Object.new
    o.send(:class_eval) do
      include Fargo::Utils
    end
    o
  }

  it "generates a correct key" do
    helper.generate_key('FOO').should == "4\220/%DCN000%/"
  end

  it "generates a correct lock and pk" do
    # there's not a whole lot of documentation about this online...
    20.times do
      lock, pk = helper.generate_lock
      pk.size.should   >= 0
      lock.size.should >= 0
    end
  end

end
