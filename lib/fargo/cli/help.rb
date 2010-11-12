module Fargo
  module CLI
    module Help

      def setup_console
        super

        add_completion(/^man\s+[^\s]*$/){
          ['man', 'results', 'search', 'ls', 'pwd', 'cwd', 'cd', 'browse',
              'download', 'get', 'who', 'say', 'send_chat', 'transfers']
        }
      end

      def man cmd = nil
        cmd ||= 'man'

        case cmd.to_sym
          when :man
            puts "Usage: man 'cmd'"
          when :results
            puts "Usage: results ['search string' | index], opts = {}"
            puts ""
            puts "  Show the results for a previous search. The search can be"
            puts "  identified by its search string or its index of the search."
            puts "  If no search string or index is given, the last search"
            puts "  results are displayed if they exist."
            puts ""
            puts "  Recognized options:"
            puts "    :full - if true, show full filenames instead of just base"
            puts "    :sort - if 'size', sort results by size"
            puts "    :grep - A regexp to filter results by"
          when :search
            puts "Usage: search ['string' | Search]"
            puts ""
            puts "  Search the hub for something. Either a string or a Search"
            puts "  object can be specified."
          when :ls
            puts "Usage: ls ['dir']"
            puts ""
            puts "  Lists a directory. If no directory is given, lists the"
            puts "  current one."
          when :pwd, :cwd
            puts "Usage: pwd/cwd"
            puts ""
            puts "  Show your current directory when browsing a user"
          when :cd
            puts "Usage: cd ['dir']"
            puts ""
            puts "  Works just like on UNIX. No argument means go to root"
          when :browse
            puts "Usage: browse 'nick'"
            puts ""
            puts "  Begin browisng a nick. If no file list has been downloaded,"
            puts "  one is queued for download and you will be notified when"
            puts "  browsing is ready."
          when :download, :get
            puts "Usage: "
          when :who
            puts "Usage: who ['nick' | 'size' | 'name']"
            puts ""
            puts "  If no argument is given, shows all users on the hub. If a"
            puts "  name is given, shows that user on the hub. If 'size' or"
            puts "  'name' is given, the users are sorted by that attribute."
          when :say, :send_chat
            puts "Usage: say/send_chat 'msg'"
            puts ""
            puts "  Send a message to the hub"
          when :transfers
            puts "Usage: transfers"
            puts ""
            puts "  Show some statistics about transfers happening."
          else
            puts "Unknown commnand: #{cmd}"
        end

      end

    end
  end
end
