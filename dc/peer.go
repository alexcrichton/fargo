package dc

import "bufio"
import "bytes"
import "compress/bzip2"
import "compress/zlib"
import "fmt"
import "errors"
import "io"
import "math/rand"
import "os"
import "regexp"
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

func (c *Client) handlePeer(in io.Reader, out io.Writer) (err error) {
  var m method
  write := bufio.NewWriter(out)

  /* Step 0 - figure out who we're talking to */
  buf := bufio.NewReader(in)
  if err = readCmd(buf, &m); err != nil { return }
  if m.name != "MyNick" { return errors.New("Expected $MyNick first") }
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
  if bad { return errors.New("Invalid state with peer tables") }
  if p.write != nil { panic("already have a write connection") }

  c.log("Connected to: " + p.nick)
  defer c.log("Disconnected from: " + p.nick)

  /* Step 2 - get their lock so we can respond with our nick/key */
  if err = readCmd(buf, &m); err != nil { return }
  if m.name != "Lock" { return errors.New("Expected $Lock second") }
  idx := bytes.IndexByte(m.data, ' ')
  if idx == -1 { return errors.New("Invalid $Lock") }

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
  if err = readCmd(buf, &m); err != nil { return }
  p.supports = make([]string, 0)
  if m.name == "Supports" {
    for _, s := range bytes.Split(m.data, []byte(" ")) {
      p.supports = append(p.supports, string(s))
    }
    if err = readCmd(buf, &m); err != nil { return }
  }

  /* Step 5 - receive their direction */
  if m.name != "Direction" { return errors.New("Expected $Direction") }
  /* Don't actually care about the direction */

  /* Step 6 - receive their key */
  if err = readCmd(buf, &m); err != nil { return }
  if m.name != "Key" { return errors.New("Expected $Key") }
  if !bytes.Equal(m.data, GenerateKey([]byte(lock))) {
    return errors.New("Invalid key received for lock send")
  }

  /* Step 7+ - upload/download files infinitely until closed */
  p.write = write
  p.state = Idle
  defer c.peerGone(nick)

  dl := func(size int64, offset int64, z bool) error {
    if p.dl == nil { return errors.New("downloading with nil download!") }
    if p.state != Downloading {
      return errors.New("not in the downloading state")
    }

    var in io.Reader = buf
    if z {
      in2, err := zlib.NewReader(in)
      if err != nil { return err }
      in = in2
    }

    _, err := p.outfile.Seek(offset, os.SEEK_SET)
    if err != nil {
      err = p.outfile.Truncate(offset)
      if err == nil {
        _, err = p.outfile.Seek(offset, os.SEEK_SET)
      }
    }
    if err != nil { return err }

    c.log("Starting download of: " + p.dl.file)
    s, err := io.CopyN(p.outfile, in, size)
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
  err = c.initiateDownload()
  defer func() {
    if err != nil {
      c.log("error with '" + nick + "': " + err.Error())
    }
  }()

  adcsnd := regexp.MustCompile("([^ ]+) (.+) ([0-9]+) ([0-9]+)( ZL1)?")
  size, offset := int64(0), int64(0)

  for err == nil {
    err = readCmd(buf, &m)
    if err != nil { return }
    switch m.name {
    /* ADC receiving half of things */
    case "ADCSND":
      parts := adcsnd.FindSubmatch(m.data)
      if len(parts) != 6 { return errors.New("Malformed ADCSND command") }
      size, err = strconv.ParseInt(string(parts[4]), 10, 32)
      if err == nil {
        offset, err = strconv.ParseInt(string(parts[3]), 10, 32)
      }
      if err == nil {
        err = dl(size, offset, len(parts[5]) != 0)
      }

    /* UGetZ?Block receiving half */
    case "Sending":
      size, err := strconv.ParseInt(string(m.data), 10, 32)
      if err == nil {
        err = dl(size, p.dl.offset, p.implements("GetZBlock"))
      }

    /* old school original DC receiving half */
    case "FileLength":
      size, err := strconv.ParseInt(string(m.data), 10, 32)
      if err == nil {
        send(write, "Send", nil)
        err = dl(size, 0, false)
      }

    default:
      c.log("Unknown command: $" + m.name)
    }
  }
  return err
}
