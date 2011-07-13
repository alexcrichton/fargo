require 'spec_helper'

describe Fargo::BlockingCounter do
  subject { Fargo::BlockingCounter.new 4 }

  it "can be decremented only the specified number of times" do
    4.times { subject.decrement }
    expect { subject.decrement }.to raise_error
  end

  it "re-awakens the waiting thread when the counter hits 0" do
    decremented = false
    Thread.start {
      4.times { subject.decrement }
      decremented = true
    }
    subject.wait
    decremented.should be_true
  end

  it "allows an initial count of 0" do
    subject = Fargo::BlockingCounter.new 0
    subject.wait
  end

  it "respects the timeout specified" do
    t = Time.now
    subject.wait 0.05
    (Time.now - t).should be_within(0.01).of(0.05)
  end

end
