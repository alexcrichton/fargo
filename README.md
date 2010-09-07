# Fargo

This gem is an implementation of the [Direct Connect (DC) protocol](http://en.wikipedia.org/wiki/Direct_Connect_\(file_sharing\)) in pure ruby.

## Installation

`gem install fargo`

## Usage

<pre>
require 'fargo'

client = Fargo::Client.new

client.configure do |config|
  config.hub_address = [address of the hub]   # Defaults to 127.0.0.1
  config.hub_port    = [port of the hub]      # Defaults to 7314
  config.passive     = true                   # Probably shouldn't mess with...
end

client.connect

client.nicks                # list of nicks registered
client.download nick, file  # download a file from a user
client.file_list nick       # get a list of files from a user

client.subscribe do |type, message|
  # type is the type of message
  # message is a hash of what was received
end
</pre>

## Limitations

As of this writing, uploading is not supported. This client can download whatever you would like, but hosting your own list of files and such isn't currently supported.

Also, active mode is not supported. Currently, you must be in passive mode.