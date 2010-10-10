require 'hirb'
require 'fargo/ext/readline'

module Fargo
  module CLI
    include Hirb::Console

    def client
      @client ||= DRbObject.new_with_uri 'druby://127.0.0.1:8082'
    end

    def results str
      results = client.search_results str

      to_print = results.map do |r|
        {
          :nick => r[:nick],
          :ext  => File.extname(r[:file]),
          :file => File.basename(r[:file].gsub("\\", '/')),
          :size => '%.2f' % [r[:size] / 1024.0 / 1024]
        }
      end

      to_print.each_with_index do |r, i|
        r[:index] = i
      end

      table to_print, :fields => [:index, :nick, :ext, :size, :file]
    end

    def search str
      client.search str
      sleep 1

      results str
    end

    def download index, search = nil
      search ||= client.searches[0]

      item = client.search_results(search)[index]

      if item.nil?
        puts 'That is not something to download!'
      else
        client.download item[:nick], item[:file], item[:tth]
      end
    end
  end
end
