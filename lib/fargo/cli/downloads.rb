module Fargo
  module CLI
    module Downloads

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
end
