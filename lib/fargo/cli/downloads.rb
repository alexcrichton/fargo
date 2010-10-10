module Fargo
  module CLI
    module Downloads
      extend ActiveSupport::Concern

      included do
        add_completion(/^download\s+\d+,\s*[^\s]*$/, &:searches)
        add_logger(:download_started) do |console, message|
          "Download of #{message[:download]['file']} " +
          "(#{console.humanize_bytes message[:download]['size']}) " +
          "from #{message[:nick]} started"
        end

        add_logger(:download_finished) do |console, message|
          "Download of #{message[:download]['file']} " +
          "finished into #{message[:file]}"
        end
      end

      def download index, search = nil
        search ||= client.searches[0]

        item = client.search_results(search)[index]

        if item.nil?
          puts 'That is not something to download!'
        else
          client.download item[:nick], item[:file], item[:tth], item[:size]
        end
      end

      def transfers
        max_nick = client.current_downloads.map{ |d| d.nick.size }.max
        client.current_downloads.each do |download|
          printf "%#{max_nick}s %10s (%.2f) %10s %s\n", download.nick,
            humanize_bytes(download.size), download.percent, download.status,
            download.file
        end

        puts "Upload slots avail: " +
          "#{client.open_upload_slots}/#{client.config.upload_slots}  " +
          "Download slots avail: " +
          "#{client.open_download_slots}/#{client.config.download_slots}"
      end

    end
  end
end
