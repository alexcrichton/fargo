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
      :type            => :search,
      :restrict_size   => false,
      :is_minimum_size => false,
      :pattern         => 'west$wing',
      :filetype        => 1,
      :address         => '128.237.66.53',
      :port            => 36565,
      :size            => 0
    }
  end

  describe 'search results' do
    context 'active searches' do
      it "correctly parses search results which are files" do
        helper.parse_message(
          "$SR notas 02 - Heroes.mp3\0053001347 "+
          "2/4\005TTH:VZWDTXHBSBSW7UMKCFHNEHXWCSWWYGU4KTIL76A " +
          "(127.0.0.1:7314)").should == {
          :type       => :search_result,
          :open_slots => 2,
          :slots      => 4,
          :hub        => 'TTH:VZWDTXHBSBSW7UMKCFHNEHXWCSWWYGU4KTIL76A',
          :file       => '02 - Heroes.mp3',
          :address    => '127.0.0.1',
          :port       => 7314,
          :size       => 3001347,
          :nick       => 'notas'
        }
      end

      it "correctly parses search results which are directories" do
        helper.parse_message(
          "$SR notas Music 2/4\005" +
          "TTH:EAAABGHTP4AAACAAAAAAAAAAACIOWCMZ6N7QAAA (127.0.0.1:7314)"
        ).should == {
          :type       => :search_result,
          :open_slots => 2,
          :slots      => 4,
          :hub        => 'TTH:EAAABGHTP4AAACAAAAAAAAAAACIOWCMZ6N7QAAA',
          :dir        => 'Music',
          :address    => '127.0.0.1',
          :port       => 7314,
          :nick       => 'notas'
        }
      end
    end

    context 'passive searches' do
      it "correctly parses search results which are files" do
        helper.parse_message(
          "$SR notas 02 - Heroes.mp3\0053001347 "+
          "2/4\005TTH:VZWDTXHBSBSW7UMKCFHNEHXWCSWWYGU4KTIL76A " +
          "(127.0.0.1:7314)\005user2").should == {
          :type       => :search_result,
          :open_slots => 2,
          :slots      => 4,
          :hub        => 'TTH:VZWDTXHBSBSW7UMKCFHNEHXWCSWWYGU4KTIL76A',
          :file       => '02 - Heroes.mp3',
          :address    => '127.0.0.1',
          :port       => 7314,
          :size       => 3001347,
          :nick       => 'notas'
        }
      end

      it "correctly parses search results which are directories" do
        helper.parse_message(
          "$SR notas Music 2/4\005" +
          "TTH:EAAABGHTP4AAACAAAAAAAAAAACIOWCMZ6N7QAAA (127.0.0.1:7314)\005nick"
        ).should == {
          :type       => :search_result,
          :open_slots => 2,
          :slots      => 4,
          :hub        => 'TTH:EAAABGHTP4AAACAAAAAAAAAAACIOWCMZ6N7QAAA',
          :dir        => 'Music',
          :address    => '127.0.0.1',
          :port       => 7314,
          :nick       => 'notas'
        }
      end
    end
  end

  describe 'the ADC draft' do
    it 'correctly parses the ADCSND command with ZL1' do
      helper.parse_message(
        "$ADCSND file TTH/PPUROLR2WSYTGPLCM3KV4V6LJC36SCTFQJFDJKA 0 1154 ZL1"
      ).should == {
        :type   => :adcsnd,
        :offset => 0,
        :file   => 'TTH/PPUROLR2WSYTGPLCM3KV4V6LJC36SCTFQJFDJKA',
        :size   => 1154,
        :zlib   => true,
        :kind   => 'file'
      }
    end

    it 'correctly parses the ADCSND command without ZL1' do
      helper.parse_message(
        "$ADCSND file TTH/PPUROLR2WSYTGPLCM3KV4V6LJC36SCTFQJFDJKA 4 1154"
      ).should == {
        :type   => :adcsnd,
        :offset => 4,
        :file   => 'TTH/PPUROLR2WSYTGPLCM3KV4V6LJC36SCTFQJFDJKA',
        :size   => 1154,
        :zlib   => false,
        :kind   => 'file'
      }
    end

    it 'correctly parses the ADCGET command with ZL1' do
      helper.parse_message(
        "$ADCGET file TTH/PPUROLR2WSYTGPLCM3KV4V6LJC36SCTFQJFDJKA 0 1154 ZL1"
      ).should == {
        :type   => :adcget,
        :offset => 0,
        :file   => 'TTH/PPUROLR2WSYTGPLCM3KV4V6LJC36SCTFQJFDJKA',
        :size   => 1154,
        :zlib   => true,
        :kind   => 'file'
      }
    end

    it 'correctly parses the ADCGET command without ZL1' do
      helper.parse_message(
        "$ADCGET file TTH/PPUROLR2WSYTGPLCM3KV4V6LJC36SCTFQJFDJKA 4 1154"
      ).should == {
        :type   => :adcget,
        :offset => 4,
        :file   => 'TTH/PPUROLR2WSYTGPLCM3KV4V6LJC36SCTFQJFDJKA',
        :size   => 1154,
        :zlib   => false,
        :kind   => 'file'
      }
    end
  end
end
