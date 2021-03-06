require_relative File.join "../boilerplate"

BOT = RedditBot::Bot.new YAML.load_file "secrets.yaml"

SUBREDDIT = "codcompetitive"

loop do
  Hearthbeat.beat "u_OpTicNaDeBoT_r_CoDCompetitive", 70 unless Gem::Platform.local.os == "darwin"
  catch :loop do

    text = " Live Streams\n\n" + [].tap do |list|

      throw :loop unless statuses = JSON.parse( begin
        NetHTTPUtils.request_data("http://streamapi.majorleaguegaming.com/service/streams/all")[/\{.+\}/m]
      rescue NetHTTPUtils::Error => e
        fail unless e.code == 408
        puts 408
        sleep 60
        retry
      end )["data"]["items"]
      games = JSON.parse(
        NetHTTPUtils.request_data("http://www.majorleaguegaming.com/api/games/all")[/\{.+\}/m]
      )["data"]["items"]
      begin
        JSON.parse begin
          NetHTTPUtils.request_data("http://www.majorleaguegaming.com/api/channels/all?fields=name,url,tags,stream_name,game_id")
        rescue NetHTTPUtils::Error => e
          fail unless e.code == 404
          puts 404
          sleep 60
          retry
        end
      rescue JSON::ParserError
        puts "JSON::ParserError"
        sleep 60
        retry
      end["data"]["items"].each do |item1|
        next unless item1["tags"].include? "COD Pro League"
        status = statuses.find{ |item2| item1["stream_name"] == item2["stream_name"] }
        next unless status && status["status"] > 0
        game = games.find{ |game| game["id"] == item1["game_id"] }
        list << "* [](#mlg) [](##{
          ["?", "live", "replay"][status["status"]]
        }) #{
          "[](##{ {
            "Call of Duty: Modern Warfare 2" => "codmw2",
            "Call of Duty: Modern Warfare 3" => "codmw3",
            "Call of Duty: Black Ops" => "codbo12",
            "Call of Duty: Black Ops II" => "codbo2",
            "Call of Duty: Black Ops III" => "codbo3",
            "Call of Duty: Advanced Warfare" => "codaw",
            "Call of Duty: Ghosts" => "codghosts2",
            "Call of Duty: Infinite Warfare" => "codiw",
          }[game["name"]] }) " if game
        }[**#{
          item1["name"]
        }**](#{
          item1["url"]
        })"
      end

      # to update access_token:
      # 0. see 'client_id' here https://www.twitch.tv/settings/connections and 'client_secret' from local ./readme file
      # 1. get 'code' by visiting in browser: https://api.twitch.tv/kraken/oauth2/authorize?response_type=code&client_id=*******&redirect_uri=http://www.example.com/unused/redirect/uri&scope=channel_read channel_feed_read
      # 2. NetHTTPUtils.request_data("https://api.twitch.tv/kraken/oauth2/token", :post, form: {client_id: "*******", client_secret: "*****", grant_type: "authorization_code", redirect_uri: "http://www.example.com/unused/redirect/uri", code: "*******"})
      twitch = lambda do |url|
        max = 1000
        data_key = "top"
        next_key = "_links"

        request = lambda do |url, acc|
          uri = URI.parse url
          query = Hash[URI.decode_www_form uri.query || ""]
          # query.merge!({ "limit" => max }) if max
          uri.query = URI.encode_www_form query.merge( {
            "access_token" => File.read("twitch.token").strip,
            "client_id" => File.read("client.id").strip,
          } )
          json = JSON.parse NetHTTPUtils.request_data uri.to_s
          unless json[data_key]
            pp json
            fail
          end
          acc = acc + json[data_key]
          next acc.take max if max && max <= acc.size
          request[json[next_key]["next"], acc]
        end

        request[url, []]
      end
      # ? absent on twitch ? "Call of Duty: Modern Warfare 2" => "codmw2"
      # t = twitch["https://api.twitch.tv/kraken/games/top?limit=100"].map{ |hash| fail hash.keys.to_s unless hash.keys == %w{ game viewers channels }; hash.values.first["name"] }
      # pp t.grep("/call of duty/i")
      # pp t.grep("/warfare/i")
      # ? absent in css    ? "Call of Duty: United Offensive"
      {
        "Call of Duty: Infinite Warfare"          => "codiw",
        "Call of Duty: Modern Warfare Remastered" => "cod4",
        "Call of Duty 4: Modern Warfare"          => "cod4",
        "Call of Duty: Modern Warfare 3"          => "codmw3",
        "Call of Duty: Black Ops"                 => "codbo12",
        "Call of Duty: Black Ops II"              => "codbo2",
        "Call of Duty: Black Ops III"             => "codbo3",
        "Call of Duty: Advanced Warfare"          => "codaw",
        "Call of Duty: Ghosts"                    => "codghosts2",
        "Call of Duty: World at War"              => "codwaw",
        "Call of Duty: WWII"                      => "codwwii",
        "Modern Warfare 2"                        => "codmw2",
      }.each do |game, css|
        (begin
          require "cgi"
          begin
            t = NetHTTPUtils.get_response "https://api.twitch.tv/kraken/streams?game=#{CGI::escape game}&access_token=#{File.read("twitch.token").strip}&client_id=#{File.read("client.id").strip}&channel=#{File.read("channels.txt").split.join ?,}"
          end while t.code == 500
          JSON.parse t.body
        rescue JSON::ParserError
          puts "JSON::ParserError"
          sleep 60
          retry
        end["streams"] || []).each do |channel|
          list << "* [](#twitch) [](#live) #{
            "[](##{css}) "
          }[**#{
            channel["channel"]["display_name"]
          }**](#{
            channel["channel"]["url"]
          })"
        end
      end

    end.join("  \n") + "\n"

    settings = BOT.json(:get, "/r/#{SUBREDDIT}/about/edit")["data"]
    # https://github.com/praw-dev/praw/blob/c45e5f6ca0c5cd9968b51301989eb82740f8dc85/praw/__init__.py#L1592
    settings.store "sr", settings.delete("subreddit_id")
    settings.store "lang", settings.delete("language")
    settings.store "link_type", settings.delete("content_options")
    settings.store "type", settings.delete("subreddit_type")
    settings.store "header-title", settings.delete("header_hover_text") || ""
    settings["domain"] ||= ""
    settings["submit_link_label"] ||= ""
    settings["submit_text_label"] ||= ""
    settings["allow_top"] = settings["allow_top"]
    settings.delete "default_set"

    prefix, postfix = CGI.unescapeHTML(settings["description"]).split(/(?<=\n#####)\s*Live Streams.+?(?=\n#+)/im)
    unless postfix
      puts "!!! can't parse sidebar !!!"
      throw :loop
    end
    next puts "nothing to change" if prefix + text + postfix == CGI.unescapeHTML(settings["description"])

    puts "updating sidebar..."
    settings["description"] = prefix + text + postfix
    _ = BOT.json :post, "/api/site_admin", settings.to_a
    fail _.inspect if _ != {"json"=>{"errors"=>[]}} && !(_["json"]["errors"].map(&:first) - ["BAD_CAPTCHA"]).empty?

  end
  sleep 300
end
