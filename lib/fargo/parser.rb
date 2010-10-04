module Fargo
  module Parser

    #
    # See <http://www.teamfair.info/DC-Protocol.htm> for more information
    #
    @@commandmatch    = /^\$(.*)$/
    @@messagematch    = /^<(.*?)> (.*)$/

    # TODO: Supports, UserIP, ops command
    # Client - hub commands
    @@validatedenied  = /^ValidateDenide/
    @@getpass         = /^GetPass$/
    @@badpass         = /^BadPass$/
    @@lock            = /^Lock (.*) Pk=.*?$/
    @@userip          = /^UserIP (.*)$/
    @@hubname         = /^HubName (.*)$/
    @@hubfull         = /^HubIsFull$/
    @@hubtopic        = /^HubTopic (.*)$/
    @@hello           = /^Hello (.*)$/
    @@myinfo          = /^MyINFO \$ALL (.*?) (.*?)\$ \$(.*?).\$(.*?)\$(.*?)\$/
    @@myinfo2         = /^MyINFO \$ALL (.*?) (.*?)\$$/
    @@to              = /^To: (.*?) From: (.*?) \$<.*?> (.*)$/
    @@hubto           = /^To: (.*?) From: Hub \$(.*)$/
    @@ctm             = /^ConnectToMe (.*?) (.*?):(.*?)$/
    @@nicklist        = /^NickList (.*?)$/
    @@psr             = /^SR (.*?) (.*?)\005(.*?) (.*?)\/(.*?)\005(.*?) \((.*?):(.*?)\)(?:\005.*)?$/
    @@psrd            = /^SR (.*?) (.*?) (.*?)\/(.*?)\005(.*?) \((.*?):(.*?)\)(?:\005.*)?$/
    @@psearch         = /^Search Hub:(.*) (.)\?(.)\?(.*)\?(.)\?(.*)$/
    @@search          = /^Search (.*):(.*) (.)\?(.)\?(.*)\?(.)\?(.*)$/
    @@oplist          = /^OpList (.*?)$/
    @@botlist         = /^BotList (.*?)$/
    @@quit            = /^Quit (.*)$/
    @@rctm            = /^RevConnectToMe (.*?) (.*?)$/

    # Client to client commands
    @@mynick     = /^MyNick (.*)$/
    @@key        = /^Key (.*)$/
    @@direction  = /^Direction (Download|Upload) (\d+)$/
    @@get        = /^Get (.*)\$(\d+)$/
    @@getzblock  = /^U?GetZBlock (.*?) (.*?) (.*?)$/
    @@send       = /^Send$/
    @@filelength = /^FileLength (.*?)$/
    @@getlistlen = /^GetListLen$/
    @@maxedout   = /^MaxedOut$/
    @@supports   = /^Supports (.*)$/
    @@error      = /^Error (.*)$/
    @@cancel     = /^Cancel$/
    @@canceled   = /^Canceled$/
    @@failed     = /^Failed (.*)$/
    @@sending    = /^Sending (.*)$/
    @@getblock   = /^U?GetBlock (.*?) (.*?) (.*)$/
    @@adcsnd     = /^ADCSND (.*?) (.*?) (.*?) (.*?)( ZL1)?$/
    @@adcget     = /^ADCGET (.*?) (.*?) (.*?) (.*?)( ZL1)?$/

    def parse_message text
      case text
        when @@commandmatch then parse_command_message $1
        when @@messagematch then {:type => :chat, :from => $1, :text => $2}
        else                     {:type => :mystery, :text => text}
      end
    end

    def parse_command_message text
      case text
        when @@validatedenied then {:type => :denide}
        when @@getpass        then {:type => :getpass}
        when @@badpass        then {:type => :badpass}
        when @@lock           then {:type => :lock, :lock => $1}
        when @@hubname        then {:type => :hubname, :name => $1}
        when @@hubfull        then {:type => :hubfull}
        when @@hubtopic       then {:type => :hubtopic, :topic => $1}
        when @@hello          then {:type => :hello, :nick  => $1}
        when @@myinfo         then {:type => :myinfo, :nick => $1,
                                    :interest => $2, :speed => $3,
                                    :email => $4, :sharesize => $5.to_i}
        when @@myinfo2        then {:type => :myinfo, :nick=> $1,
                                    :interest => $2, :sharesize => 0}
        when @@to             then {:type => :privmsg, :to => $1, :from => $2,
                                    :text => $3}
        when @@hubto          then {:type => :privmsg, :to => $1,
                                    :from => 'Hub', :text => $2}
        when @@ctm            then {:type => :connect_to_me, :nick => $1,
                                    :address => $2, :port => $3.to_i}
        when @@nicklist       then {:type => :nick_list,
                                    :nicks => $1.split('$$')}
        when @@psr            then {:type => :search_result, :nick => $1,
                                    :file => $2, :size => $3.to_i,
                                    :open_slots => $4.to_i, :slots => $5.to_i,
                                    :hub => $6, :address => $7,
                                    :port => $8.to_i}
        when @@psrd           then {:type => :search_result, :nick => $1,
                                    :dir => $2,
                                    :open_slots => $3.to_i, :slots => $4.to_i,
                                    :hub => $5, :address => $6,
                                    :port => $7.to_i}
        when @@psearch        then {:type => :search, :searcher => $1,
                                    :restrict_size => $2 == 'T',
                                    :is_minimum_size => $3 == 'F',
                                    :size => $4.to_i, :filetype => $5.to_i,
                                    :pattern => $6}
        when @@search         then {:type => :search, :address => $1,
                                    :port => $2.to_i,
                                    :restrict_size => $3 == 'T',
                                    :is_minimum_size => $4 == 'F',
                                    :size => $5.to_i,
                                    :filetype => $6.to_i, :pattern => $7}
        when @@oplist         then {:type => :op_list,
                                    :nicks => $1.split('$$')}
        when @@oplist         then {:type => :bot_list,
                                    :nicks => $1.split('$$')}
        when @@quit           then {:type => :quit, :nick => $1}
        when @@rctm           then {:type => :revconnect, :who => $1}

        when @@mynick         then {:type => :mynick, :nick => $1}
        when @@key            then {:type => :key, :key => $1}
        when @@direction      then {:type => :direction,
                                    :direction => $1.downcase,
                                    :number => $3.to_i}
        when @@get            then {:type => :get, :file => $1,
                                    :offset => $2.to_i - 1, :size => -1}
        when @@send           then {:type => :send}
        when @@filelength     then {:type => :file_length, :size => $1.to_i}
        when @@getlistlen     then {:type => :getlistlen}
        when @@maxedout       then {:type => :noslots}
        when @@supports       then {:type => :supports,
                                    :extensions => $1.split(' ')}
        when @@error          then {:type => :error, :message => $1}
        when @@failed         then {:type => :error, :message => $1}
        when @@cancel         then {:type => :cancel}
        when @@canceled       then {:type => :canceled}
        when @@sending        then {:type => :sending, :size => $1.to_i}
        when @@adcsnd         then {:type => :adcsnd, :kind => $1, :file => $2,
                                    :offset => $3.to_i, :size => $4.to_i,
                                    :zlib => !$5.nil?}
        when @@adcget         then {:type => :adcget, :kind => $1, :file => $2,
                                    :offset => $3.to_i, :size => $4.to_i,
                                    :zlib => !$5.nil?}
        when @@getzblock      then {:type => :getblock, :file => $3,
                                    :size => $2.to_i, :offset => $1.to_i,
                                    :zlib => true}
        when @@getblock       then {:type => :getblock, :start => $1.to_i,
                                    :size => $2.to_i, :file => $3}
        when @@userip         then
          h = {:type => :userip, :users => {}}
          $1.split('$$').map{ |s| h[:users][s.split(' ')[0]] = s.split(' ')[1]}
          h
        else                       {:type => :mystery, :text => '$' + text}
      end
    end
  end
end
