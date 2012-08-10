package fargo

import "bufio"
import "bytes"
import "compress/bzip2"
import "compress/zlib"
import "fmt"
import "errors"
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

var NotIdle = errors.New("client not idle")

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

func (c *Client) peerGone(nick string) {
  c.Lock()
  p := c.peers[nick]
  if p == nil {
    panic("removing unknown peer")
  }
  delete(c.peers, nick)
  for _, dl := range p.dls {
    c.failed = append(c.failed, dl)
  }
  if p.outfile != nil {
    p.outfile.Close()
    os.Remove(p.outfile.Name())
  }
  if p.dl != nil {
    c.failed = append(c.failed, p.dl)
    c.DL.release()
  }
  c.Unlock()
  c.initiateDownload()
}

func (c *Client) initiateDownload() (err error) {
  if !c.DL.take() { return }
  defer func() {
    if err != nil { c.DL.release() }
  }()

  c.Lock()
  defer c.Unlock()

  /* If we can't create our destination file, then this is a fatal error. If we
   * can't actually download a file from anyone because everyone's already
   * downloading, then this isn't fatal. */
  var dl *download
  for _, peer := range c.peers {
    dl = peer.pop()
    if dl == nil { continue }
    dst, err := dl.destination(c.DownloadRoot)
    if err != nil { return err }
    file, err := os.Create(dst)
    if err != nil { return err }
    if peer.download(file, dl) == nil {
      break
    }
    os.Remove(dst)
    peer.push(dl)
    dl = nil
  }
  /* if we didn't start a download with anyone, then release the slot we got */
  if dl == nil {
    c.DL.release()
  }

  return nil
}

func (p *peer) pop() *download {
  if len(p.dls) == 0 {
    return nil
  }
  dl := p.dls[0]
  p.dls = p.dls[1:]
  return dl
}

func (p *peer) push(dl *download) {
  p.dls = append(p.dls, dl)
}

func (p *peer) download(outfile *os.File, dl *download) error {
  p.Lock()
  defer p.Unlock()
  if dl == nil { panic("can't download nothing") }
  if p.state != Idle { return NotIdle }
  if p.write == nil { panic("idle without a write connection!") }

  if dl.fileList() {
    if p.implements("XmlBZList") {
      dl.file = "files.xml.bz2"
    } else if p.implements("BZList") {
      dl.file = "MyList.bz2"
    } else {
      panic("Can't download file list")
    }
  }

  p.state = Downloading
  p.outfile = outfile
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
  return nil
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
  if readCmd(buf, &m) != nil { return }
  if m.name != "MyNick" { return }
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
  if bad { return }
  if p.write != nil { panic("already have a write connection") }

  c.log("Connected to: " + p.nick)
  defer c.log("Disconnected from: " + p.nick)

  /* Step 2 - get their lock so we can respond with our nick/key */
  if readCmd(buf, &m) != nil { return }
  if m.name != "Lock" { return }
  idx := bytes.IndexByte(m.data, ' ')
  if idx == -1 { return }

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
  if readCmd(buf, &m) != nil { return }
  p.supports = make([]string, 0)
  if m.name == "Supports" {
    for _, s := range bytes.Split(m.data, []byte(" ")) {
      p.supports = append(p.supports, string(s))
    }
    if readCmd(buf, &m) != nil { return }
  }

  /* Step 5 - receive their direction */
  if m.name != "Direction" { return }
  /* Don't actually care about the direction */

  /* Step 6 - receive their key */
  if readCmd(buf, &m) != nil { return }
  if m.name != "Key" { return }
  if !bytes.Equal(m.data, GenerateKey([]byte(lock))) { return }

  /* Step 7+ - upload/download files infinitely until closed */
  p.write = write
  p.state = Idle
  defer c.peerGone(nick)

  dl := func(out io.Writer, in io.Reader, size int64, z bool) error {
    if p.dl == nil { return errors.New("downloading with nil download!") }
    if out == nil { return errors.New("downloading without an output file") }
    if p.state != Downloading {
      return errors.New("not in the downloading state")
    }

    if z {
      in2, err := zlib.NewReader(in)
      if err != nil { return err }
      in = in2
    }

    c.log("Starting download of: " + p.dl.file)
    s, err := io.CopyN(out, in, size)
    if err != nil { return err }
    if s != size { return errors.New("Didn't download whole file") }
    if p.dl.fileList() {
      _, err := p.outfile.Seek(0, os.SEEK_SET)
      if err != nil { return err }
      err = p.parseFiles(p.outfile)
      if err != nil { return err }
    }
    c.log("Finished downloading: " + p.dl.file)
    p.state = Idle
    c.DL.release() /* if we fail with error, our slot is released elsewhere */
    p.dl = nil
    p.outfile = nil
    return c.initiateDownload()
  }

  /* try to diagnose why peers disconnect */
  err := c.initiateDownload()
  defer func() {
    if err != nil {
      c.log("error with '" + nick + "' :" + err.Error())
    }
  }()

  for err == nil {
    err = readCmd(buf, &m)
    if err != nil { return }
    switch m.name {
    /* ADC receiving half of things */
    case "ADCSND":
      parts := bytes.Split(m.data, []byte(" "))
      if len(parts) < 4 { return }
      s, err := strconv.ParseInt(string(parts[3]), 10, 32)
      if err == nil {
        err = dl(p.outfile, buf, s, len(parts) == 5)
      }

    /* UGetZ?Block receiving half */
    case "Sending":
      s, err := strconv.ParseInt(string(m.data), 10, 32)
      if err == nil {
        err = dl(p.outfile, buf, s, p.implements("GetZBlock"))
      }

    /* old school original DC receiving half */
    case "FileLength":
      s, err := strconv.ParseInt(string(m.data), 10, 32)
      if err == nil {
        send(write, "Send", nil)
        err = dl(p.outfile, buf, s, false)
      }

    default:
      c.log("Unknown command: $" + m.name)
    }
  }
}
