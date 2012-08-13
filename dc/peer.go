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
  state peerState
  dl    *download
  file  *os.File
  ul    *File
  dls   []*download
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
var ClientFileNotFound = errors.New("file not found")

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
  if p.file != nil {
    p.file.Close()
    if p.dl != nil {
      os.Remove(p.file.Name())
    }
    p.file = nil
  }
  if p.dl != nil {
    c.failed = append(c.failed, p.dl)
    c.DL.release()
    p.dl = nil
  } else if p.ul != nil {
    if p.ul.Name != "files.xml.bz2" {
      c.UL.release()
    }
    p.ul = nil
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
  p.file = outfile
  p.dl = dl

  if p.implements("ADCGet") {
    sendf(p.write, "ADCGET", func(w *bufio.Writer) {
      if dl.tth != "" && p.implements("TTHF") {
        fmt.Fprintf(w, "tthl TTH/%s", dl.tth)
      } else {
        fmt.Fprintf(w, "file %s", dl.file)
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
      fmt.Fprintf(w, "%s$%d", dl.file, dl.offset + 1)
    })
  }
  return nil
}

func (p *peer) upload(c *Client, file string,
                      offset, size int64) (int64, error) {
  err := ClientFileNotFound

  /* MiniSlots dictates that file lists don't need upload slots */
  if file != "files.xml.bz2" {
    /* take a slot, convert to upload state, set p.ul with open file */
    if !c.UL.take() { return 0, errors.New("No slots to upload with") }
    defer func() {
      if err != nil { c.UL.release() }
    }()
  }

  p.Lock()
  defer p.Unlock()
  if p.state != Idle { return 0, NotIdle }
  info := c.shares.query(file)
  if info == nil { return 0, ClientFileNotFound }
  handle, err := os.Open(info.realpath)
  if err != nil { return 0, err }

  p.state = Uploading
  p.ul = info
  p.file = handle
  err = nil
  if offset + size > int64(info.Size) || size == -1 {
    return int64(info.Size) - offset, nil
  }
  return size, nil
}

func (p *peer) implements(extension string) bool {
  for _, s := range p.supports {
    if extension == s {
      return true
    }
  }
  return false
}

func (p *peer) parseFiles(c *Client, in io.Reader) error {
  files := &FileListing{}
  err := ParseFileList(bzip2.NewReader(in), files)
  if err == nil {
    c.Lock()
    c.lists[p.nick] = files
    c.Unlock()
  }
  return err
}

func (c *Client) handlePeer(in io.Reader, out io.Writer, first bool) (err error) {
  var m method
  write := bufio.NewWriter(out)
  number := rand.Int63n(0x7fff)
  lock, pk := GenerateLock()

  if first {
    send(write, "MyNick", []byte(c.Nick))
    sendf(write, "Lock", func(w *bufio.Writer) {
      fmt.Fprintf(w, "%s Pk=%s", lock, pk)
    })
  }

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
  if !first {
    send(write, "MyNick", []byte(c.Nick))
    sendf(write, "Lock", func(w *bufio.Writer) {
      fmt.Fprintf(w, "%s Pk=%s", lock, pk)
    })
  }
  send(write, "Supports",
       []byte("MiniSlots XmlBZList ADCGet ZLIG GetZBlock TTHF"))
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
    if p.state != Downloading {
      return errors.New("not in the downloading state")
    }
    if p.dl == nil { return errors.New("downloading with nil download") }
    if p.ul != nil { return errors.New("downloading while uploading") }
    defer p.file.Close()

    var in io.Reader = buf
    if z {
      in2, err := zlib.NewReader(in)
      if err != nil { return err }
      in = in2
    }

    _, err := p.file.Seek(offset, os.SEEK_SET)
    if err != nil {
      err = p.file.Truncate(offset)
      if err == nil {
        _, err = p.file.Seek(offset, os.SEEK_SET)
      }
    }
    if err != nil { return err }

    c.log("Starting download of: " + p.dl.file)
    s, err := io.CopyN(p.file, in, size)
    if err != nil { return err }
    if s != size { return errors.New("Didn't download whole file") }
    if p.dl.fileList() {
      _, err := p.file.Seek(0, os.SEEK_SET)
      if err != nil { return err }
      err = p.parseFiles(c, p.file)
      if err != nil { return err }
    }
    c.log("Finished downloading: " + p.dl.file)
    c.DL.release() /* if we fail with error, our slot is released elsewhere */
    p.dl = nil
    p.file = nil
    p.state = Idle
    return c.initiateDownload()
  }

  ul := func(size int64, offset int64, z bool) error {
    if p.state != Uploading { return errors.New("not in the uploading state") }
    if p.dl != nil { return errors.New("uploading while trying to download") }
    if p.ul == nil { return errors.New("uploading without a file") }
    defer p.file .Close()

    /* Don't upload through the bufio.Writer instance */
    var compressed *zlib.Writer
    var upload io.Writer = out
    if z {
      compressed = zlib.NewWriter(upload)
      upload = compressed
    }
    write.Flush()

    _, err := p.file.Seek(offset, os.SEEK_SET)
    if err != nil { return err }

    c.log("Starting upload of: " + p.file.Name())
    _, err = io.CopyN(upload, p.file, size)
    if compressed != nil && err == nil {
      err = compressed.Close() /* be sure to flush the zlib stream */
    }
    if err != nil { return err }
    c.log("Finished uploading: " + p.file.Name())
    if p.ul.Name != "files.xml.bz2" {
      c.UL.release() /* if we fail with error, our slot is released elsewhere */
    }
    p.ul = nil
    p.file = nil
    p.state = Idle
    return c.initiateDownload()
  }

  /* try to diagnose why peers disconnect */
  err = c.initiateDownload()
  defer func() {
    if err != nil && err != io.EOF {
      c.log("error with '" + nick + "': " + err.Error())
    }
  }()

  adc := regexp.MustCompile("([^ ]+) (.+) ([0-9]+) (-?[0-9]+)( ZL1)?")
  size, offset := int64(0), int64(0)

  for err == nil {
    err = readCmd(buf, &m)
    if err != nil { return }
    switch m.name {
    /* ADC receiving half of things */
    case "ADCSND", "ADCGET":
      parts := adc.FindStringSubmatch(string(m.data))
      if len(parts) != 6 {
        return errors.New("Malformed ADC command: " + string(m.data))
      }
      size, err = strconv.ParseInt(parts[4], 10, 64)
      if err == nil {
        offset, err = strconv.ParseInt(parts[3], 10, 64)
      }
      if err != nil { return err }
      zlig := len(parts[5]) != 0

      if m.name == "ADCSND" {
        err = dl(size, offset, zlig)
      } else {
        size, err = p.upload(c, parts[2], offset, size)
        if err != nil { return err }
        sendf(write, "ADCSND", func(w *bufio.Writer) {
          fmt.Fprintf(w, "%s %s %d %d", parts[1], parts[2], offset, size)
          if zlig {
            w.WriteString(" ZL1")
          }
        })
        err = ul(size, offset, zlig)
      }

    /* UGetZ?Block receiving half */
    case "Sending":
      size, err := strconv.ParseInt(string(m.data), 10, 64)
      if err == nil {
        err = dl(size, p.dl.offset, p.implements("GetZBlock"))
      }

    /* old school original DC receiving half */
    case "FileLength":
      size, err := strconv.ParseInt(string(m.data), 10, 64)
      if err == nil {
        send(write, "Send", nil)
        err = dl(size, 0, false)
      }

    /* old school DC download system */
    case "Get":
      parts := bytes.Split(m.data, []byte("$"))
      if len(parts) != 2 { return errors.New("Malformed Get command") }
      file := string(parts[0])
      offset, err = strconv.ParseInt(string(parts[1]), 10, 64)
      offset--

      size, err = p.upload(c, file, offset, -1)
      if err != nil { return err }

      sendf(write, "FileLength", func(w *bufio.Writer) {
        fmt.Fprintf(w, "%d", size)
      })
      err = readCmd(buf, &m)
      if err != nil { return err }
      if m.name != "Send" { return errors.New("Expected $Send") }

      err = ul(size, offset, false)

    /* Upload half of UGetZ?Block */
    case "UGetBlock", "UGetZBlock":
      parts := bytes.SplitN(m.data, []byte(" "), 3)
      if len(parts) != 3 { return errors.New("Malformed UGetZ?Block command") }
      offset, err = strconv.ParseInt(string(parts[0]), 10, 64)
      if err != nil { return err }
      size, err = strconv.ParseInt(string(parts[1]), 10, 64)
      if err != nil { return err }
      size, err = p.upload(c, string(parts[2]), offset, size)
      if err != nil { return err }

      sendf(write, "Sending", func(w *bufio.Writer) {
        fmt.Fprintf(w, "%d", size)
      })
      err = ul(size, offset, m.name == "UGetZBlock")

    default:
      return errors.New("Unknown command: $" + m.name)
    }
  }
  return err
}
