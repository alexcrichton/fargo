module Fargo
  module CLI
    module Downloads

      def setup_console
        super

        add_completion(/^(download|get)\s+\d+,\s*[^\s]*$/) do
          client.searches
        end

        add_logger(:download_started) do |message|
          "Download of #{message[:download][:file]} " +
          "(#{humanize_bytes message[:length]}) " +
          "from #{message[:nick]} started"
        end

        add_logger(:download_finished) do |message|
          "Download of #{message[:download][:file]} " +
          "finished into #{message[:file]}"
        end
      end

      def download index, search = nil
        search ||= client.searches[0]

        if search.nil?
          puts "Nothing to download!"
          return
        end

        item = client.search_results(search)[index]

        if item.nil?
          puts 'That is not something to download!'
        else
          client.download item[:nick], item[:file], item[:tth], item[:size]
        end
      end

      def transfers
        max_nick = client.current_downloads.keys.map(&:size).max
        client.current_downloads.each_pair do |nick, download|
          printf "%#{max_nick}s %10s (%5.2f%%) -- %s\n", nick,
            humanize_bytes(download.size), 100 * download.percent,
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
