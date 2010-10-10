require 'active_support/core_ext/module/delegation'

module Fargo
  module CLI
    module Searches
      extend ActiveSupport::Concern

      included do
        add_completion(/^results\s+[^\s]+$/, &:searches)
        delegate :search, :to => :client
      end

      def results str = nil, opts = {}
        str ||= client.searches.last
        results = client.search_results(str).dup

        if results.nil?
          puts "No search results for: #{str.inspect}!"
          return
        end

        results.each_with_index{ |r, i|
          r[:file]  = File.basename(r[:file].gsub("\\", '/'))
          r[:index] = i
        }

        max_nick_size = results.map{ |r| r[:nick].size }.max

        if opts[:sort] == 'size'
          results = results.sort_by{ |r| r[:size] }
        elsif !opts[:sort].nil?
          puts "Unknown sort value: #{opts[:sort]}"
          results = []
        end

        if opts[:grep]
          results = results.select{ |r| r[:file].match opts[:grep] }
        end

        results.each do |r|
          printf "%3d: %#{max_nick_size}s %9s -- %s\n", r[:index],
            r[:nick], humanize_bytes(r[:size]), r[:file]
        end

        true
      end

    end
  end
end
