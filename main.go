package main

import "net"
import "os"

import "./ui"
import "./dc"

func ip() string {
  name, err := os.Hostname()
  if err != nil { panic(err) }
  addrs, err := net.LookupHost(name)
  if err != nil { panic(err) }
  if len(addrs) == 0 { panic("no ip address") }
  return addrs[0]
}

func main() {
  term := ui.NewTerminal()
  go term.Start()
  defer term.Stop()

  var client dc.Client
  client.HubAddress    = "127.0.0.1:7314"
  client.ClientAddress = net.JoinHostPort(ip(), "65317")
  client.Input         = term
  client.Nick          = "foobar"
  client.DLSlots       = 4
  client.Run(term.Cmds)
}
