require_relative "../boilerplate"

BOT = RedditBot::Bot.new YAML.load_file "secrets.yaml"
SUBREDDIT = "CouncilOfRicks"

CSS_CLASS = "blueflair"

require "csv"

ignored = []
loop do
  names, flairs = begin
    JSON.load begin
      NetHTTPUtils.request_data File.read "gas.url"
    rescue NetHTTPUtils::Error => e
      fail e unless [404, 500].include? e.code
      puts "smth wrong with GAS script"
      sleep 60
      retry
    end
  rescue JSON::ParserError
    puts "smth wrong with GAS script"
    sleep 60
    retry
  end

  existing = BOT.json(:get, "/r/#{SUBREDDIT}/api/flairlist", limit: 1000)["users"]
  fail if existing.size >= 1000

  if names.size != flairs.size
    puts "columns are different by length -- probably someone is editing the Spreadsheet"
  else
    names.zip(flairs).drop(1).map(&:flatten).map do |user, text|
      user = user.to_s.strip
      next unless user[/\A[a-z-_\d]+\z/i]
      text = text.to_s.strip
      next puts "ignored #{user}" if ignored.include? user
      next if existing.include?( {"user"=>user, "flair_text"=>text, "flair_css_class"=>CSS_CLASS} )
      [user, text, CSS_CLASS]
    end.compact.each_slice(50) do |slice|
      load = CSV.generate do |csv|
        slice.each &csv.method(:<<)
      end
      BOT.json(:post, "/r/#{SUBREDDIT}/api/flaircsv", flair_csv: load).each do |report|
        unless report.values_at("errors", "ok", "warnings") == [{}, true, {}]
          pp report
          abort "wrong keys" unless report.keys.sort == %w{ errors ok status warnings }
          abort "wrong values" unless report.values_at(*%w{ ok status warnings }) == [false, "skipped", {}]
          abort "wrong error keys" unless report["errors"].keys == %w{ user }
          abort "wrong error values" unless user = report["errors"]["user"][/\Aunable to resolve user `([A-Za-z-_\d]+)', ignoring\z/, 1]
          ignored |= [user]
        end
      end
    end
  end

  sleep 300
end
