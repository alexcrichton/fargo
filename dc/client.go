package dc

import "../ui"

type Client struct {
  port int
}

func NewClient() *Client {
  return &Client{7314}
}

func (c *Client) Run(input ui.Input) {
  for {
    switch input.ReceiveCommand() {
      case ui.Quit:
        input.Log("exiting...")
        return
    }
  }
}
