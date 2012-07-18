package dc

import "bufio"
import "bytes"
import "compress/bzip2"
import "compress/zlib"
import "fmt"
import "io"
import "math/rand"
import "net"
import "os"
import "strconv"
import "sync"

type peer struct {
  nick     string
  write    *bufio.Writer
  supports []string

  sync.Mutex
  state   peerState
  dl      *download
  outfile *os.File
  dls     []*download

  files *FileListing
}

type peerState int

const (
  Uninitialized peerState = iota
  RequestingConnection
  Connecting
  Idle
  Downloading
  Uploading
)

func (c *Client) peer(nick string, cb func(*peer)) *peer {
  c.Lock()

  p := c.peers[nick]
  if p == nil {
    p = &peer{dls: make([]*download, 0), nick: nick}
    c.peers[nick] = p
  }
  p.Lock()
  c.Unlock()
  cb(p)
  p.Unlock()
  return p
}

func (d *download) fileList() bool {
  return d.file == FileList
}

func (p *peer) download(dl *download) {
  p.Lock()
  defer p.Unlock()

  /* TODO: not here */
  if dl == nil {
    if len(p.dls) == 0 {
      return
    } else {
      dl = p.dls[0]
      p.dls = p.dls[1:]
    }
  }

  /* TODO: manage downloads elsewhere */
  if p.state != Idle {
    p.dls = append(p.dls, dl)
    return
  }
  p.state = Downloading
  if p.write == nil {
    panic("no write connection")
  }

  if dl.fileList() {
    if p.implements("XmlBZList") {
      dl.file = "files.xml.bz2"
    } else if p.implements("BZList") {
      dl.file = "MyList.bz2"
    } else {
      panic("Can't download file list")
    }
  }

  /* TODO: get file from elsewhere */
  f, err := os.Create("files.xml.bz2")
  if err != nil {
    panic("couldn't open")
  }
  p.outfile = f
  p.dl = dl

  if p.implements("ADCGet") {
    sendf(p.write, "ADCGET", func(w *bufio.Writer) {
      w.WriteString("file ")
      if dl.tth != "" && p.implements("TTHF") {
        w.WriteString("TTH/")
        w.WriteString(dl.tth)
      } else {
        w.WriteString(dl.file)
      }
      fmt.Fprintf(w, " %d %d", dl.offset, dl.size)
      if p.implements("ZLIG") {
        w.WriteString(" ZL1")
      }
    })
  } else if p.implements("GetZBlock") {
    sendf(p.write, "UGetZBlock", func(w *bufio.Writer) {
      fmt.Fprintf(w, "%d %d %s", dl.offset, dl.size, dl.file)
    })
  } else if p.implements("XmlBZList") {
    sendf(p.write, "UGetBlock", func(w *bufio.Writer) {
      fmt.Fprintf(w, "%d %d %s", dl.offset, dl.size, dl.file)
    })
  } else {
    sendf(p.write, "Get", func(w *bufio.Writer) {
      fmt.Fprintf(w, "%s$%d", dl.file, dl.offset+1)
    })
  }
}

func (p *peer) implements(extension string) bool {
  for _, s := range p.supports {
    if extension == s {
      return true
    }
  }
  return false
}

func (p *peer) parseFiles(in io.Reader) error {
  files := &FileListing{}
  err := ParseFileList(bzip2.NewReader(in), files)
  if err == nil {
    p.files = files
  }
  return err
}

func (c *Client) readPeer(conn net.Conn) {
  defer conn.Close()
  var m method
  write := bufio.NewWriter(conn)

  /* Step 0 - figure out who we're talking to */
  buf := bufio.NewReader(conn)
  if readCmd(buf, &m) != nil {
    return
  }
  if m.name != "MyNick" {
    return
  }
  nick := string(m.data)

  /* Step 1 - make sure we have the only connection to the peer */
  bad := false
  p := c.peer(nick, func(p *peer) {
    if p.state == Uninitialized || p.state == RequestingConnection {
      p.state = Connecting
    } else {
      bad = true
    }
  })
  if bad {
    return
  }
  if p.write != nil {
    panic("already have a write connection")
  }

  c.log("Connected to: " + p.nick)
  defer c.log("Disconnected from: " + p.nick)

  /* Step 2 - get their lock so we can respond with our nick/key */
  if readCmd(buf, &m) != nil {
    return
  }
  if m.name != "Lock" {
    return
  }
  idx := bytes.IndexByte(m.data, ' ')
  if idx == -1 {
    return
  }

  /* Step 3 - send our nick/lock/supports/direction metadata */
  number := rand.Int63n(0x7fff)
  lock, pk := GenerateLock()
  send(write, "MyNick", []byte(c.Nick))
  sendf(write, "Lock", func(w *bufio.Writer) {
    fmt.Fprintf(w, "%s Pk=%s", lock, pk)
  })
  send(write, "Supports",
    []byte("MiniSlots XmlBZList ADCGet TTHF ZLIG GetZBlock"))
  mydirection := "Upload"
  if len(p.dls) > 0 {
    mydirection = "Download"
  }
  sendf(write, "Direction", func(w *bufio.Writer) {
    fmt.Fprintf(w, "%s %d", mydirection, number)
  })
  send(write, "Key", GenerateKey(m.data[0:idx]))

  /* Step 4 - receive what they support (optional) */
  if readCmd(buf, &m) != nil {
    return
  }
  p.supports = make([]string, 0)
  if m.name == "Supports" {
    for _, s := range bytes.Split(m.data, []byte(" ")) {
      p.supports = append(p.supports, string(s))
    }
    if readCmd(buf, &m) != nil {
      return
    }
  }

  /* Step 5 - receive their direction */
  if m.name != "Direction" {
    return
  }
  /* Don't actually care about the direction */

  /* Step 6 - receive their key */
  if readCmd(buf, &m) != nil {
    return
  }
  if m.name != "Key" {
    return
  }
  if !bytes.Equal(m.data, GenerateKey([]byte(lock))) {
    return
  }

  /* Step 7+ - upload/download files infinitely until closed */
  p.write = write
  p.state = Idle
  p.download(nil) /* attempt to start downloading something */

  dl := func(out io.Writer, in io.Reader, size int64, z bool) (int64, error) {
    if p.dl == nil {
      panic("downloading with nil download!")
    }
    if out == nil {
      panic("downloading without an output file")
    }
    if p.state != Downloading {
      panic("not in the downloading state")
    }

    if z {
      in2, err := zlib.NewReader(in)
      if err != nil {
        return 0, err
      }
      in = in2
    }

    c.log("Starting download of: " + p.dl.file)
    defer c.log("Finished downloading: " + p.dl.file)
    s, err := io.CopyN(out, in, size)
    if p.dl.fileList() && s == size && err == nil {
      p.outfile.Seek(0, os.SEEK_SET)
      err := p.parseFiles(p.outfile)
      if err != nil {
        c.log("Couldn't parse file list: " + err.Error())
      }
    }
    return s, err
  }

  for {
    if readCmd(buf, &m) != nil {
      return
    }
    switch m.name {
    /* ADC receiving half of things */
    case "ADCSND":
      parts := bytes.Split(m.data, []byte(" "))
      if len(parts) < 4 {
        return
      }
      s, err := strconv.ParseInt(string(parts[3]), 10, 32)
      if err != nil {
        return
      }
      var d int64 = s

      s, err = dl(p.outfile, buf, d, len(parts) == 5)
      if d != s || err != nil {
        return
      }

    /* UGetZ?Block receiving half */
    case "Sending":
      s, err := strconv.ParseInt(string(m.data), 10, 32)
      if err != nil {
        return
      }
      s2, err := dl(p.outfile, buf, s, p.implements("GetZBlock"))
      if err != nil || s2 != s {
        return
      }

    /* old school original DC receiving half */
    case "FileLength":
      s, err := strconv.ParseInt(string(m.data), 10, 32)
      if err != nil {
        return
      }
      send(write, "Send", nil)
      s2, err := dl(p.outfile, buf, s, false)
      if err != nil || s2 != s {
        return
      }

    default:
      c.log("Unknown command: $" + m.name)
    }
  }
}
