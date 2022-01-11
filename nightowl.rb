#!/usr/bin/env ruby
### REQUIRE AND INSTALL
require 'bundler/inline'
require 'optparse'
require 'yaml'
gemfile do
  source 'https://rubygems.org'
  gem 'rb-inotify'
  gem 'rconrb', require: 'rcon'
  gem 'colorize'
end

### Setup globals
$options = {}
$config = {}
$client = nil
$shutdown_in_progress = false
$checker_in_progress = false

### Custom logger
def custom_log(msg, color, log_to_rcon: true)
  puts msg.colorize(color)
  if log_to_rcon 
    rcon_msg = "<nightowl> "+msg
    $client.execute("say "+rcon_msg)
  end
end

### METHODS FOR STARTING/STOPPING SHUTDOWN
def shutdown_server()
  if $shutdown_in_progress
    custom_log("! Shutdown procedure already in progress", :red)
  else
    custom_log("| Starting shutdown procedure", :cyan)
    $shutdown_in_progress = true
    Thread.new {
      countdown = 15
      while $shutdown_in_progress && countdown > 0
        custom_log("- #{countdown}s until shutdown", :yellow)
        sleep 1
        countdown = countdown - 1
        if countdown == 0
          # Now actually shutdown the server
          custom_log("| Executing shutdown", :cyan)
          $client.execute("stop")
          `shutdown +5`
          exit
        end
      end
    }
  end
end

def cancel_shutdown()
  if $shutdown_in_progress
    $shutdown_in_progress = false
    custom_log("| Cancelling shutdown procedure", :cyan)
  else
    custom_log("! No shutdown to cancel", :red)
  end
end

### PLAYER CHECKER FUNCS

def get_player_count()
  return $client.execute("list").body.split[2].to_i
end

def run_player_checker()
  if $checker_in_progress
    custom_log("! Player count checker already running", :red)
  else
    $checker_in_progress = true
    custom_log("| Starting player count checker", :cyan)
    Thread.new{
      consecutive_empties = 0;
      while $checker_in_progress
        # Check for players
        custom_log("| Checking for players", :cyan, log_to_rcon: false)
        player_count = get_player_count()
        # Update number of times 0 players detected
        if player_count == 0
          consecutive_empties = consecutive_empties + 1
          custom_log("- No players found #{consecutive_empties} time(s) in a row", :yellow, log_to_rcon: false)
        else
          consecutive_empties = 0
          custom_log("- Found #{player_count} players", :yellow, log_to_rcon: false)
        end
        if consecutive_empties >= 2
          # Trigger shutdown if empty twice in a row
          shutdown_server()
        else
          # Else sleep and wait to check again
          # We sleep in intervals of 1 so that we can cancel the checker if need be
          countdown = $options[:time]
          while countdown > 0 && $checker_in_progress
            countdown = countdown - 1
            sleep 1
          end
        end
      end
    }
  end
end

def cancel_player_checker()
  if $checker_in_progress
    $checker_in_progress = false
    custom_log("| Pausing player count checker", :cyan)
  else 
    custom_log("! Player count checker is not running", :red)
  end
end

### LOGFILE WATCHER

def inspect_logfile(logfile)
  # Get newline
  newline = IO.readlines(logfile).last(1)[0]
  # Don't allow commands from Dynmap
  if newline.include? "WEB"
    return
  end
  # Check for nightowl commands
  if newline.include? "nightowl sleep"
    shutdown_server()
  elsif newline.include? "nightowl cancel"
    cancel_shutdown()
  elsif newline.include? "nightowl resume"
    run_player_checker()
  elsif newline.include? "nightowl pause"
    cancel_player_checker()
  end
end

#### MAIN SCRIPT
# Option parsing
$options = {
  :file => "logs/latest.log",
  :time => 60*30,
  :config => "nightowl_config.yml"
}
OptionParser.new do |opts|
  opts.on('-f', '--file [logfile]', "Log file to watch (default logs/latest.log)") do |f|
    $options[:file] = f
  end
  opts.on('-t', '--time [wait_time]', Integer, "Time (in mins) between player count checks (default 30min)") do |t|
    $options[:time] = t * 60
  end
  opts.on('-c', '--config [config_file]', "YAML file containing RCON config (default nightowl_config.yml)") do |c|
    $options[:config] = c
  end
end.parse!

# Parse config file
defaults = {
  "host" => "localhost",
  "port" => 25575,
  "password" => ""
}
if File.file?($options[:config]) then
  $config = YAML.load_file($options[:config])
else
  $config = {} 
end
defaults.each_key do |key|
  if $config[key].nil? then $config[key] = defaults[key] end
end

# Setup RCON
$client = Rcon::Client.new(host: $config["host"],
                          port: $config["port"],
                          password: $config["password"])
msg="Connecting to RCON server on #{$config["host"]}:#{$config["port"]}"
begin
  $client.authenticate!(ignore_first_packet: false)
rescue
  abort "! RCON client failed to connect".red
else
  custom_log("✓ RCON client connected", :green, log_to_rcon: false)
end

# Setup log watcher
if not File.file?($options[:file])
  abort "! Logfile #{$options[:file]} does not exist".red
end
notifier = INotify::Notifier.new
notifier.watch($options[:file], :modify) {
  inspect_logfile($options[:file])
}
Thread.new{ notifier.run }
custom_log("✓ Setup logfile listener", :green, log_to_rcon: false)

# Setup player counter
run_player_checker()

# Loop
while true
  sleep 10
end
