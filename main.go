package main

import "./ui"
import "./dc"

func main() {
  term := ui.NewTerminal()
  client := dc.NewClient()
  go term.Start()
  defer term.Stop()
  client.Run(term)
}
