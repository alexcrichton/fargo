module Fargo
  module CLI
    module Stats

      def status
        puts "User count: #{client.nicks.size}"
        puts "Shared Directories:"
        client.shared_directories.each do |dir|
          puts "\t#{dir}"
        end
        puts "Sharing: #{humanize_bytes(client.share_size)}"
      end

    end
  end
end
