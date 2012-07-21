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

  default_config := os.Getenv("HOME") + "/.fargo/config"
  user_config := flag.String("config", "",
                             "config file of commands to run before startup")
  flag.Parse()

  config := *user_config
  if config == "" {
    config = default_config
  }
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
  } else if *user_config != "" {
    log.Fatal(err)
  }

  term.Run()
}
