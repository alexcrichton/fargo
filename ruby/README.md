# Fargo

This gem is an implementation of the [Direct Connect (DC) protocol](http://en.wikipedia.org/wiki/Direct_Connect_\(file_sharing\)) in ruby.

## Installation

`gem install fargo`

## Configuration

For a full list of configuration options, see [the source](http://github.com/alexcrichton/fargo/blob/master/lib/fargo/client.rb).

Whatever the configuration directory is (by default `~/.fargo`), if there is a file called 'config' located in it, it will be eval'ed when Fargo is started. This way you can call `Fargo.configure` to set a nick, the hub address, share directories, and such.

The configuration directory will also be used as a location to store the local file list caches.

## CLI Usage

The CLI for Fargo works like an IRB session (it actually is an IRB session!). It's got helper methods and tab completion, however, to make things a lot easier.

Here's a synopsis of what the console has for you:

  * `search 'str'` - search for a string on the hub. You will be notified when results arrive
  * `results 'str'` - see the results for the given search
  * `download 0, str=nil` - download the 0th numbered result from the search for 'str'. By default this uses the last given search
  * `get 0, str=nil` - same as `download`
  * `who 'str'=nil` - show a list of users on the hub when no argument is given. Otherwise print out specific information for the given user. If the user is 'name' or 'size', the users will be sorted based off of that attribute
  * `browse 'nick'` - download nick's file list and begin browsing them. This works like a regular shell where you have a current directory and you 'cd' and 'ls' all the time
  * `cd 'dir'` - change directorires
  * `ls 'dir'` - list a directory
  * `get 'file'` - begin downloading of a file (relative to the current dir)
  * `download 'file'` - same as 'get "file"'
  * `transfers` - see what's being downloaded/uploaded (percentages included)
  * `status` - show some information about what you're sharing
  * `say 'msg'` - say 'msg' on the hub (also `send_chat`)

All of the methods are just wrappers around the `client` object available in the IRB session. They just manipulate the return values, provide tab completion, and format results.

If you wanna get lower level access, the `client` method returns the client to interact with.

### Multiple Instances

By default, the CLI tries to connect to an instance of Fargo over DRb at 'localhost:8082'. If this fails, the CLI spawns a new thread with the EventMachine reactor running inside of it to use.

If you would like to have multiple applications using the same instance of Fargo on the same machine, simply have one process start up and call

<pre>
  DRb.start_service 'druby://localhost:8082', Fargo::Client.new
</pre>

You can also [configure it](http://github.com/alexcrichton/cohort_radio/blob/master/lib/fargo/daemon.rb) or do whatever in the process as well.

## Programmatic Usage

<pre>
require 'fargo'

client = Fargo::Client.new

client.configure do |config|
  config.hub_address = [address of the hub]   # Defaults to 127.0.0.1
  config.hub_port    = [port of the hub]      # Defaults to 7314
  config.passive     = true                   # Defaults to false
  config.address     = '1.2.3.4'              # Defaults to machine IP
  config.active_port = [port to listen on]    # Defaults to 7315
  config.search_port = [port to listen on]    # Defaults to 7316
end

EventMachine.run {
  client.connect

  client.nicks                # list of nicks registered
  client.download nick, file  # download a file from a user
  client.file_list nick       # get a list of files from a user

  client.channel.subscribe do |type, message|
    # type is the type of message
    # message is a hash of what was received
  end
}
</pre>

See `lib/fargo/client.rb` for a full list of configuration options

## Compatibility

Fargo should run on both ruby 1.8 and ruby 1.9. It's been tested on 1.8.7 and 1.9.2

## MIT License

Copyright (c) 2010 Alex Crichton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
