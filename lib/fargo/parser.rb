module Fargo
  module Parser

    #
    # See <http://www.teamfair.info/DC-Protocol.htm> for more information
    #
    @@commandmatch    = /\$(.*)$/
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
    @@psr             = /^SR (.*?) (.*?)\005(.*?) (.*?)\/(.*?)\005(.*?) \((.*?):(.*?)\)$/
    @@psearch         = /^Search Hub:(.*) (.)\?(.)\?(.*)\?(.)\?(.*)$/
    @@search          = /^Search (.*):(.*) (.)\?(.)\?(.*)\?(.)\?(.*)$/
    @@oplist          = /^OpList (.*?)$/
    @@botlist         = /^BotList (.*?)$/
    @@quit            = /^Quit (.*)$/
    @@sr              = /^SR (.*?) (.*?)\005(.*?) (.*?)\/(.*?)\005(.*?) (.*?):(.*?)$/
    @@rctm            = /^RevConnectToMe (.*?) (.*?)$/

    # Client to client commands
    @@mynick        = /^MyNick (.*)$/
    @@key           = /^Key (.*)$/
    @@direction     = /^Direction (Download|Upload) (\d+)$/
    @@get           = /^Get (.*)\$(\d+)$/
    @@send          = /^Send$/
    @@filelength    = /^FileLength (.*?)$/
    @@getlistlen    = /^GetListLen$/
    @@maxedout      = /^MaxedOut$/
    @@supports      = /^Supports (.*)$/
    @@error         = /^Error (.*)$/
    @@ugetblock     = /^UGetBlock (.*?) (.*?) (.*)$/
    @@adcsnd        = /^ADCSND (.*?) (.*?) (.*?) (.*?)$/
    @@adcsnd_zl1    = /^ADCSND (.*?) (.*?) (.*?) (.*?) ZL1$/

    def parse_message text
      case text
        when @@commandmatch then parse_command_message $1
        when @@messagematch then {:type => :chat, :from => $1, :text => $2}
        when ''             then {:type => :garbage}
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
        when @@hubname        then {:type => :hubfull}
        when @@hubtopic       then {:type => :hubtopic, :topic => $1}
        when @@hello          then {:type => :hello, :who  => $1}
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
        when @@psearch        then {:type => :search, :searcher => $1,
                                    :restrict_size => $2, :min_size => $3.to_i,
                                    :size => $4.to_i, :filetype => $5,
                                    :query => $6}
        when @@search         then {:type => :search, :address => $1,
                                    :port => $2.to_i, :restrict_size => $3,
                                    :min_size => $4.to_i, :size => $5.to_i,
                                    :filetype => $6, :query => $7}
        when @@oplist         then {:type => :op_list,
                                    :nicks => $1.split('$$')}
        when @@oplist         then {:type => :bot_list,
                                    :nicks => $1.split('$$')}
        when @@quit           then {:type => :quit, :who => $1}
        when @@sr             then {:type => :search_result, :nick => $2,
                                    :file => $3,:size => $4.to_i,
                                    :open_slots => $5.to_i, :slots => $6.to_i,
                                    :hubname => $7}
        when @@rctm           then {:type => :revconnect, :who => $1}

        when @@mynick         then {:type => :mynick, :nick => $1}
        when @@key            then {:type => :key, :key => $1}
        when @@direction      then {:type => :direction,
                                    :direction => $1.downcase,
                                    :number => $3.to_i}
        when @@get            then {:type => :get, :path => $1,
                                    :offset => $2.to_i - 1}
        when @@send           then {:type => :send}
        when @@filelength     then {:type => :file_length, :size => $1.to_i}
        when @@getlistlen     then {:type => :getlistlen}
        when @@maxedout       then {:type => :noslots}
        when @@supports       then {:type => :supports,
                                    :extensions => $1.split(' ')}
        when @@error          then {:type => :error, :message => $1}
        when @@adcsnd_zl1     then {:type => :adcsnd, :kind => $1, :tth => $2,
                                    :offset => $3.to_i, :size => $4.to_i,
                                    :zlib => true}
        when @@adcsnd         then {:type => :adcsnd, :kind => $1, :tth => $2,
                                    :offset => $3.to_i, :size => $4.to_i}
        when @@ugetblock      then {:type => :ugetblock, :start => $1.to_i,
                                    :finish => $2.to_i, :path => $3}
        when @@userip         then
          h = {:type => :userip, :users => {}}
          $1.split('$$').map{ |s| h[:users][s.split(' ')[0]] = s.split(' ')[1]}
          h
        else                       {:type => :mystery, :text => text}
      end
    end
  end
end
