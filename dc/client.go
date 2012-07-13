package dc

import "bufio"
import "bytes"
import "io"
import "fmt"
import "math/rand"
import "net"
import "strconv"
import "compress/zlib"

import "../ui"

type Client struct {
  HubAddress    string
  ClientAddress string
  Input         ui.Input
  Nick          string
  Passive       bool
  DLSlots       int
  ULSlots       int

  peers         map[string] *peer
  dls           map[string] []*download
  hub           hubConn
  dir_query     chan string
  dir_response  chan string
  peer_new      chan *peer
  peer_gone     chan string
  peer_idle     chan string
}

type download struct {
  nick   string
  file   string
  tth    string
  offset uint64
  size   int64
}

type hubConn struct {
  write *bufio.Writer
  name  string
  nicks []string
  ops   []string
  validated bool
}

type method struct {
  name string
  data []byte
}

func (c *Client) Run(cmds chan ui.Command) {
  c.peers        = make(map[string]*peer)
  c.dls          = make(map[string] []*download)
  c.dir_query    = make(chan string)
  c.dir_response = make(chan string)
  c.peer_new     = make(chan *peer)
  c.peer_gone    = make(chan string)
  c.peer_idle    = make(chan string)
  methods := make(chan *method)

  if !c.Passive { go c.activeServer() }

  for {
    select {
      case nick := <-c.dir_query:
        if c.dls[nick] == nil || len(c.dls[nick]) == 0 {
          c.dir_response <- "Upload"
        } else {
          c.dir_response <- "Download"
        }

      case p := <-c.peer_new:
        if c.peers[p.nick] != nil { panic("already connected peer!") }
        c.peers[p.nick] = p

      case p := <-c.peer_gone:
        if c.peers[p] == nil { panic("no peer available!") }
        delete(c.peers, p)

      case n := <-c.peer_idle:
        arr := c.dls[n]
        p := c.peers[n]
        if arr != nil && len(arr) > 0 && p.download(arr[0]) {
          c.dls[n] = arr[1:]
        }

      case cmd := <-cmds:
        switch cmd {
          case ui.Quit:
            c.Input.Log("exiting...")
            return

          case ui.Connect:
            if c.hub.write != nil {
              c.Input.Log("already connected")
              continue
            }
            conn, err := net.Dial("tcp", c.HubAddress)
            if err != nil {
              c.Input.Log("error connecting: " + err.Error())
              continue
            }
            c.hub.write = bufio.NewWriter(conn)
            go c.readHub(conn, methods)

          case ui.Nicks:
            for _, n := range c.hub.nicks { c.Input.Log(n) }
          case ui.Ops:
            for _, n := range c.hub.ops { c.Input.Log(n) }

          case ui.Browse:
            nick := c.hub.nicks[2] /* TODO: get from ui */
            c.download(NewDownload(nick, "files.xml.bz2"))
        }

      case m := <-methods:
        switch m.name {
          case "Lock":
            idx := bytes.IndexByte(m.data, ' ')
            if idx == -1 { panic("bad lock cmd") }
            send(c.hub.write, "Key", GenerateKey(m.data[0:idx]))

          case "HubName":
            c.hub.name = string(m.data)
            if !c.hub.validated {
              send(c.hub.write, "ValidateNick", []byte(c.Nick))
            }

          case "Hello":
            c.hub.validated = true
            c.Input.Log("Connected to hub: " + c.hub.name)
            send(c.hub.write, "Version", []byte("1,0091"))
            sendf(c.hub.write, "MyINFO", func(w *bufio.Writer) {
              var b byte
              if c.Passive {
                b = 'P'
              } else {
                b = 'A'
              }
              fmt.Fprintf(w, "$ALL %s ", c.Nick)
              fmt.Fprintf(w, "<fargo V:0.0.1,M:%c,H:1/0/0,S:%d,Dt:1.2.6/W>",
                          b, c.ULSlots)
              /* $speed\001$email$size$ */
              w.WriteString("$ $DSL\001$$5368709121$")
            })
            send(c.hub.write, "GetNickList", nil)

          case "NickList":
            nicks := bytes.Split(m.data, []byte("$$"))
            c.hub.nicks = make([]string, 0)
            for _, name := range nicks {
              c.hub.nicks = append(c.hub.nicks, string(name))
            }
          case "OpList":
            ops := bytes.Split(m.data, []byte("$$"))
            c.hub.ops = make([]string, 0)
            for _, name := range ops {
              c.hub.ops = append(c.hub.ops, string(name))
            }

          case "RevConnectToMe":
            nicks := bytes.Split(m.data, []byte(" "))
            remote := string(nicks[0])
            if c.Passive && c.peers[remote] != nil {
              c.Input.Log("Connection couldn't be made to '" + string(remote) +
                          "' because both clients are passive")
            } else if c.Passive {
              /* right back at you */
              c.recvconnect(remote)
            } else {
              panic("not implemented")
            }

          default:
            c.Input.Log("Unknown command: $" + m.name + " " + string(m.data))
        }

    }
  }
}

func (c *Client) activeServer() {
  ln, err := net.Listen("tcp", c.ClientAddress)
  if err != nil { panic(err) }
  for {
    conn, err := ln.Accept()
    if err != nil { panic(err) }
    go c.readPeer(conn)
  }
}

func sendf(w *bufio.Writer, meth string, f func(*bufio.Writer)) {
  w.WriteByte('$')
  w.WriteString(meth)
  w.WriteByte(' ')
  f(w)
  w.WriteByte('|')
  w.Flush()
}

func send(w *bufio.Writer, meth string, data []byte) {
  w.WriteByte('$')
  w.WriteString(meth)
  if data != nil {
    w.WriteByte(' ')
    w.Write(data)
  }
  w.WriteByte('|')
  w.Flush()
}

func parseMethod(m *method, msg []byte) {
  components := bytes.SplitN(msg[1:], []byte(" "), 2)
  m.name = string(components[0])
  if len(components) == 2 {
    m.data = components[1]
  }
}

func (c *Client) readHub(conn net.Conn, methods chan *method) {
  buf := bufio.NewReader(conn)

  for {
    cmd, err := buf.ReadBytes('|')
    if err == io.EOF {
      break;
    } else if err != nil {
      panic(err)
    }
    cmd = cmd[0:len(cmd)-1]
    if cmd[0] == '$' {
      m := &method{}
      parseMethod(m, cmd)
      methods <- m
    } else if cmd[0] == '<' {
      c.Input.Log(string(cmd))
    } else {
      panic("bad read from hub")
    }
  }
}

func readCmd(buf *bufio.Reader, m *method) error {
  cmd, err := buf.ReadBytes('|')
  if err != nil { return err }
  parseMethod(m, cmd[0:len(cmd)-1])
  return nil
}

func (c *Client) readPeer(conn net.Conn) {
  defer conn.Close()
  var m method
  var p peer
  write := bufio.NewWriter(conn)
  p.write = write

  /* Step 1 - figure out who we're talking to */
  buf := bufio.NewReader(conn)
  if readCmd(buf, &m) != nil { return }
  if m.name != "MyNick" { return }
  p.nick = string(m.data)
  c.Input.Log("Connected to: " + p.nick)
  defer c.Input.Log("Disconnected from: " + p.nick)

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
  c.dir_query <- p.nick
  mydirection := <-c.dir_response
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
  c.peer_new <- &p
  c.peer_idle <- p.nick
  defer func() { c.peer_gone <- p.nick }()

  dl := func(out io.Writer, in io.Reader, size int64, z bool) (int64, error) {
    if p.dl == nil { panic("downloading with nil download!") }
    if p.outfile == nil { panic("downloading without an output file") }
    if p.state != Downloading { panic("not in the downloading state") }

    if z {
      in2, err := zlib.NewReader(in)
      if err != nil { return 0, err }
      in = in2
    }

    c.Input.Log("Starting download of: " + p.dl.file)
    defer c.Input.Log("Finished downloading: " + p.dl.file)
    return io.CopyN(out, in, size)
  }

  for {
    if readCmd(buf, &m) != nil { return }
    switch m.name {
      case "ADCSND":
        parts := bytes.Split(m.data, []byte(" "))
        if len(parts) < 4 { return }
        s, err := strconv.ParseInt(string(parts[3]), 10, 32)
        if err != nil { return }
        var d int64 = s

        s, err = dl(p.outfile, buf, d, len(parts) == 5)
        if d != s || err != nil { return }

      default:
        c.Input.Log("Unknown command: $" + m.name)
    }
  }
}

func (c *Client) recvconnect(nick string) {
  sendf(c.hub.write, "RevConnectToMe", func(w *bufio.Writer) {
    w.WriteString(c.Nick)
    w.WriteByte(' ')
    w.WriteString(nick)
  });
}

func (c *Client) connect(nick string) {
  sendf(c.hub.write, "ConnectToMe", func(w *bufio.Writer) {
    w.WriteString(nick)
    w.WriteByte(' ')
    w.WriteString(c.ClientAddress)
  })
}

func (c *Client) download(dl *download) {
  l := c.dls[dl.nick]
  if l == nil {
    l = make([]*download, 0)

    /* TODO: fix this */
    if c.Passive {
      c.recvconnect(dl.nick)
    } else {
      c.connect(dl.nick)
    }
  }
  c.dls[dl.nick] = append(l, dl)
}

func NewDownload(nick string, file string) *download {
  return &download{nick:nick, file:file, size:-1}
}
