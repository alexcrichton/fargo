package main

import "log"
import "net"
import "os"

import "./ui"
import "./dc"

func ip() string {
  name, err := os.Hostname()
  if err != nil {
    log.Fatal(err)
  }
  addrs, err := net.LookupHost(name)
  if err != nil {
    log.Fatal(err)
  }
  if len(addrs) == 0 {
    log.Fatal("no ip address")
  }
  return addrs[0]
}

func main() {
  client := dc.NewClient()
  client.HubAddress = "127.0.0.1:7314"
  client.ClientAddress = net.JoinHostPort(ip(), "65317")
  client.Nick = "foobar"
  client.DLSlots = 4
  client.DownloadRoot = "downloads"

  term := ui.New(client)
  term.Run()
}
