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
def print_help()
  help_msg = [
    '? nightowl sleep - Start the shutdown procedure; in 15 seconds the server will stop and 5 minutes later turn off the PC.',
    '? nightowl cancel - Cancel a shutdown procedure.',
    '? nightowl pause - Pause polling for inactivity.',
    '? nightowl resume - Resume polling for inactivity.',
    '? nightowl help - Print the help message'
  ]
  help_msg.each{ |line| say_to_rcon(line) }
end

def custom_log(msg, color, log_to_rcon: true)
  puts msg.colorize(color)
  if log_to_rcon 
    say_to_rcon(msg)
  end
end

def say_to_rcon(msg)
    rcon_msg = "<nightowl> "+msg
    $client.execute("say "+rcon_msg)
end

### METHODS FOR STARTING/STOPPING SHUTDOWN
def shutdown_server()
  if $shutdown_in_progress
    custom_log("! Shutdown procedure already in progress", :red)
  else
    custom_log("- Starting shutdown procedure", :cyan)
    $shutdown_in_progress = true
    Thread.new {
      countdown = 15
      while $shutdown_in_progress && countdown > 0
        custom_log("| #{countdown}s until shutdown", :yellow)
        sleep 1
        countdown = countdown - 1
        if countdown == 0
          # Now actually shutdown the server
          custom_log("- Executing shutdown", :cyan)
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
    custom_log("- Cancelling shutdown procedure", :cyan)
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
    custom_log("- Starting player count checker", :cyan)
  end
end

def cancel_player_checker()
  if $checker_in_progress
    $checker_in_progress = false
    custom_log("- Pausing player count checker", :cyan)
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
  elsif newline.include? "nightowl help"
    print_help()
  end
end

#### MAIN SCRIPT
# Option parsing
$options = {
  :file => "logs/latest.log",
  :time => 30,
  :config => "nightowl_config.yml"
}
OptionParser.new do |opts|
  opts.on('-f', '--file [logfile]', "Log file to watch (default logs/latest.log)") do |f|
    $options[:file] = f
  end
  opts.on('-t', '--time [wait_time]', Integer, "Time (in mins) between player count checks (default 30min)") do |t|
    $options[:time] = t
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
notifier_thread = Thread.new{ notifier.run }
custom_log("✓ Setup logfile listener", :green, log_to_rcon: false)

# Setup player counter
consecutive_empties = 0;
loop do
  sleep 60
  # Skip check if checker paused
  if not $checker_in_progress
    consecutive_empties = 0;
    next
  end
  # Check for players
  player_count = get_player_count()
  if player_count == 0
    consecutive_empties = consecutive_empties + 1
    custom_log("| No players found #{consecutive_empties} minute(s) in a row", :yellow, log_to_rcon: false)
  else
    consecutive_empties = 0
    custom_log("| Found #{player_count} players", :yellow, log_to_rcon: false)
  end
  # Stop server if we've seen 0 many times in a row
  # We do strict inueqlaity to ensure its been at least $options[:time] minutes
  if consecutive_empties > $options[:time]
    # Stop the player checker to prevent more looping
    cancel_player_checker()
    # Trigger shutdown if empty twice in a row
    shutdown_server()
  end
end
