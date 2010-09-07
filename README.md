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
