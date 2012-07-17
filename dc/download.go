package dc

type download struct {
  nick   string
  file   string
  tth    string
  offset uint64
  size   int64
}

const FileList = "files.xml.bz2"

func (c *Client) download(dl *download) {
  p := c.peer(dl.nick, func(p *peer) {
    if p.state != Uninitialized {
      return
    }
    if c.Passive {
      c.recvconnect(dl.nick)
    } else {
      c.connect(dl.nick)
    }
    p.state = RequestingConnection
  })
  p.download(dl)
}

func NewDownload(nick string, file string) *download {
  return &download{nick: nick, file: file, size: -1}
}
