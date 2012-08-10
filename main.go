package main

import "bufio"
import "flag"
import "io"
import "log"
import "os"

import "./ui"
import "./dc"

func main() {
  client := dc.NewClient()
  term   := ui.New(client)

  var cache, config string
  home := os.Getenv("HOME") + "/.fargo"
  flag.StringVar(&config, "config", home + "/config",
                 "config of commands to run before startup")
  flag.StringVar(&cache, "cache", home,
                 "cache directory for internal files")
  flag.Parse()

  file, err := os.Open(config)
  if err == nil {
    println("Reading commands from:", config)
    in := bufio.NewReader(file)
    for {
      s, err := in.ReadString('\n')
      if err == io.EOF {
        break
      } else if err != nil {
        log.Fatal(err)
      }
      term.Exec(s[0:len(s)-1])
    }
  } else if config != home + "/config" {
    log.Fatal(err)
  }

  client.CacheDir = cache
  client.SpawnHashers()
  term.Run()
}
