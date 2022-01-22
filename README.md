# nightowl

This script lets you automatically stop your Minecraft server and shutdown your PC under a number of conditions:

1. If a user says `nightowl sleep`
2. Nobody has been logged onto the server for a while

For now, authentication is provided by the whitelist on your server.

## Usage
Here's the usage from `./nightowl.rb -h`
```
Usage: nightowl [options]
    -f, --file [logfile]             Log file to watch (default logs/latest.log)
    -t, --time [wait_time]           Time (in mins) between player count checks (default 30min)
    -c, --config [config_file]       YAML file containing RCON config (default nightowl_config.yml)
```

## Config file
Here is an illustrative example:
```
host: "localhost"
port: 25575
password: "something-nobody-would-ever-guess"
```

## In-game Usage
To interact with `nightowl` just type commands into the in-game chat.
There are four commands:

* `nightowl sleep` - Start the shutdown procedure; in 15 seconds the server will stop and 5 minutes later turn off the PC.
* `nightowl cancel` - Cancel a shutdown procedure.
* `nightowl pause` - Pause polling for inactivity.
* `nightowl resume` - Resume polling for inactivity.
* `nightowl help` - Print the help message

## TODO

* Refactor so that starting/stopping threads has a better API.
* Refactor so that all options/config can be set through both `YAML` file and command-line options.
* Make sure that we only respond to chat messages or server messages.
* Add whitelist to config.
