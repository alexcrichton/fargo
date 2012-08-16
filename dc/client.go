package dc

import "bufio"
import "bytes"
import "errors"
import "fmt"
import "io"
import "log"
import "net"
import "path"
import "regexp"
import "strconv"
import "strings"
import "sync"

type Client struct {
  /* configuration options */
  HubAddress    string
  ClientAddress string
  Nick          string
  Passive       bool
  DL            Slots
  UL            Slots
  DownloadRoot  string
  CacheDir      string
  Quiet         bool
  Hub           HubConnection

  logc   chan string
  peers  map[string]*peer
  lists  map[string]*FileListing
  dls    map[string][]*download
  failed []*download
  shares Shares

  sync.Mutex
}

type Slots struct {
  Cnt int
  sync.Mutex
}

type dirRequest struct {
  nick string
  resp chan string
}

type HubConnection struct {
  Name  string

  conn  net.Conn
  write *bufio.Writer
  nicks map[string]*NickInfo
  ops   []string
}

type NickInfo struct {
  Status  string
  Client  string
  Version string
  Mode    string
  Slots   uint32
  Speed   string
  Email   string
  Shared  ByteSize
}

type method struct {
  name string
  data []byte
}

var notConnected = errors.New("not connected to the Hub")
var infoPattern = regexp.MustCompile(`\$ALL (\S*) (.*)\$ \$(\S*)` + "\001?" +
                                     `\$(\S*)\$(\S*)\$`)
var tagPattern = regexp.MustCompile(`(.*)<(.*) V:(.*),M:(.),H:\d+/\d+/\d+` +
                                    `,S:(\d+).*>`)

func (h *HubConnection) parseInfo(info string) error {
  matches := infoPattern.FindStringSubmatch(info)
  if len(matches) != 6 { return errors.New("Malformed info string") }
  ni := h.nicks[matches[1]]
  if ni == nil { return errors.New("MyINFO for an unknown nick") }

  size, err := strconv.ParseInt(matches[5], 10, 64)
  if err != nil { return err }

  ni.Speed  = matches[3]
  ni.Email  = matches[4]
  ni.Shared = ByteSize(size)

  status := tagPattern.FindStringSubmatch(matches[2])

  if len(status) == 6 {
    slots, err := strconv.ParseInt(status[5], 10, 32)
    if err != nil { return err }
    ni.Status  = strings.TrimSpace(status[1])
    ni.Client  = status[2]
    ni.Version = status[3]
    ni.Mode    = status[4]
    ni.Slots   = uint32(slots)
  } else {
    ni.Status  = matches[2]
    ni.Client  = ""
    ni.Version = ""
    ni.Mode    = ""
    ni.Slots   = 0
  }

  return nil
}

func NewClient() *Client {
  return &Client{Passive: true,
                 peers:   make(map[string]*peer),
                 lists:   make(map[string]*FileListing),
                 dls:     make(map[string][]*download),
                 failed:  make([]*download, 0),
                 shares:  NewShares(),
                 Hub:     HubConnection{nicks: make(map[string]*NickInfo),
                                        ops:   make([]string, 0)}}
}

func (c *Client) log(msg string) {
  if !c.Quiet {
    if c.logc == nil {
      println(msg)
    } else {
      c.logc <- msg
    }
  }
}

func (s *Slots) take() bool {
  s.Lock()
  defer s.Unlock()
  if s.Cnt > 0 {
    s.Cnt--
    return true
  }
  return false
}

func (s *Slots) release() {
  s.Lock()
  s.Cnt++
  s.Unlock()
}

func (c *Client) run() {
  /* spawn off our active server to receive incoming connections */
  if !c.Passive {
    ln, err := net.Listen("tcp", c.ClientAddress)
    if err != nil {
      log.Fatal("Couldn't spawn active server at '" +
                c.ClientAddress + "': ", err)
    }
    /* if specified via ':xxx' then resolve host here */
    c.ClientAddress = ln.Addr().String()
    go func() {
      for {
        conn, err := ln.Accept()
        if err != nil {
          break
        }
        go func() {
          c.handlePeer(conn, conn, true)
          conn.Close()
        }()
      }
      c.log("Active server shut down")
    }()
    defer ln.Close()
  }

  /* Create the tcp connection to the Hub */
  conn, err := net.Dial("tcp", c.HubAddress)
  if err != nil {
    c.log("error connecting: " + err.Error())
    return
  }
  c.HubAddress = conn.RemoteAddr().String()
  if c.Hub.conn != nil {
    panic("already have Hub connection")
  }
  c.Hub.conn = conn
  c.Hub.write = bufio.NewWriter(conn)
  defer func() {
    c.Hub.conn = nil
    c.Hub.write = nil
  }()
  Hub := bufio.NewReader(conn)
  var m method
  defer c.log("Hub disconnected")

  /* Step 1 - Receive the Hub's lock */
  if readCmd(Hub, &m) != nil { return }
  if m.name != "Lock" { return }
  idx := bytes.IndexByte(m.data, ' ')
  if idx == -1 { return }

  /* Step 2 - Receive the Hub's name */
  if readCmd(Hub, &m) != nil { return }
  if m.name != "HubName" { return }
  c.Hub.Name = string(m.data)
  c.log("Connected to Hub: " + c.Hub.Name)

  /* Step 3 - send our credentials */
  send(c.Hub.write, "Key", GenerateKey(m.data[0:idx]))
  send(c.Hub.write, "ValidateNick", []byte(c.Nick))

  /* Step 4 - receive our $Hello and reply with our info */
  if readCmd(Hub, &m) != nil {
    return
  }
  if m.name != "Hello" {
    return
  }
  if string(m.data) != c.Nick {
    return
  }
  send(c.Hub.write, "Version", []byte("1,0091"))
  sendf(c.Hub.write, "MyINFO", func(w *bufio.Writer) {
    var b byte
    if c.Passive {
      b = 'P'
    } else {
      b = 'A'
    }
    fmt.Fprintf(w, "$ALL %s ", c.Nick)
    fmt.Fprintf(w, "<fargo V:0.0.1,M:%c,H:1/0/0,S:%d>",
                b, c.UL.Cnt)
    /* $speed\001$email$size$ */
    /* TODO: real file size */
    w.WriteString("$ $DSL\001$$5368709121$")
  })
  send(c.Hub.write, "GetNickList", nil)

  /* Step 4+ - process commands from the Hub as they're received */
  for {
    cmd, err := Hub.ReadBytes('|')
    if err != nil {
      return
    }
    cmd = cmd[0 : len(cmd)-1]
    if cmd[0] == '$' {
      parseMethod(&m, cmd)
      c.hubExec(&m)
    } else if cmd[0] == '<' {
      c.log(string(cmd))
    } else {
      break
    }
  }
}

func (c *Client) hubExec(m *method) {
  switch m.name {
  case "NickList":
    nicks := bytes.Split(m.data, []byte("$$"))
    c.Lock()
    for _, name := range nicks {
      nick := string(name)
      if len(name) > 0 && c.Hub.nicks[nick] == nil {
        c.Hub.nicks[nick] = &NickInfo{}
        sendf(c.Hub.write, "GetINFO", func(w *bufio.Writer) {
          fmt.Fprintf(w, "%s %s", nick, c.Nick)
        })
      }
    }
    c.Unlock()

  case "Hello":
    nick := string(m.data)
    c.Lock()
    if c.Hub.nicks[nick] == nil {
      c.Hub.nicks[nick] = &NickInfo{}
    }
    c.Unlock()

  case "Quit":
    c.Lock()
    delete(c.Hub.nicks, string(m.data))
    c.Unlock()

  case "MyINFO":
    err := c.Hub.parseInfo(string(m.data))
    if err != nil {
      c.log("MyINFO error: " + err.Error() + " for: " + string(m.data))
    }

  case "HubName":
    if c.Hub.Name != string(m.data) {
      c.Hub.Name = string(m.data)
      c.log("Hub renamed to: " + c.Hub.Name)
    }

  case "OpList":
    ops := bytes.Split(m.data, []byte("$$"))
    sops := make([]string, 0)
    for _, name := range ops {
      if len(name) > 0 {
        sops = append(sops, string(name))
      }
    }
    c.Hub.ops = sops

  case "RevConnectToMe":
    nicks := bytes.Split(m.data, []byte(" "))
    remote := string(nicks[0])
    if c.Passive && c.peers[remote] != nil {
      c.log("Connection couldn't be made to '" + string(remote) +
        "' because both clients are passive")
    } else if c.Passive {
      /* right back at you */
      c.recvconnect(remote)
    } else {
      c.connect(remote)
    }

  case "ConnectToMe":
    parts := bytes.Split(m.data, []byte(" "))
    if len(parts) != 2 { break }
    if string(parts[0]) != c.Nick { break }
    go func() {
      c.log("Connecting to: " + string(m.data))
      conn, err := net.Dial("tcp", string(parts[1]))
      if err == nil {
        err = c.handlePeer(conn, conn, true)
      }
      if err != nil && err != io.EOF {
        c.log("Connection failed: " + err.Error())
      }
      if conn != nil { conn.Close() }
    }()

  default:
    c.log("Unknown command: $" + m.name + " " + string(m.data))
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

func readCmd(buf *bufio.Reader, m *method) error {
  cmd, err := buf.ReadBytes('|')
  if err != nil {
    return err
  }
  parseMethod(m, cmd[0:len(cmd)-1])
  return nil
}

func (c *Client) recvconnect(nick string) {
  sendf(c.Hub.write, "RevConnectToMe", func(w *bufio.Writer) {
    w.WriteString(c.Nick)
    w.WriteByte(' ')
    w.WriteString(nick)
  })
}

func (c *Client) connect(nick string) {
  sendf(c.Hub.write, "ConnectToMe", func(w *bufio.Writer) {
    w.WriteString(nick)
    w.WriteByte(' ')
    w.WriteString(c.ClientAddress)
  })
}

func (c *Client) Browse(nick string) error {
  if c.Hub.write == nil {
    return notConnected
  }
  return c.download(NewDownload(nick, FileList))
}

func (c *Client) Nicks() []string {
  c.Lock()
  nicks := make([]string, len(c.Hub.nicks))
  i := 0
  for k, _ := range c.Hub.nicks {
    nicks[i] = k
    i++
  }
  c.Unlock()
  return nicks
}

func (c *Client) Ops() ([]string, error) {
  return c.Hub.ops, nil
}

func (c *Client) ConnectHub(msgs chan string) error {
  if c.Nick == "" { return errors.New("no nick is configured") }
  if c.HubAddress == "" { return errors.New("no Hub address is configured") }
  if c.DownloadRoot == "" { return errors.New("no download root is configured")}
  if !c.Passive && c.ClientAddress == "" {
    return errors.New("no client address is configured")
  }
  if c.Hub.write == nil {
    c.logc = msgs
    go c.run()
    return nil
  }
  return errors.New("already connected to the Hub")
}

func (c *Client) DisconnectHub() error {
  if c.Hub.conn == nil {
    return notConnected
  }
  return c.Hub.conn.Close()
}

func (c *Client) Listings(nick string, dir string) (*Directory, error) {
  c.Lock()
  list := c.lists[nick]
  c.Unlock()

  if list == nil {
    return nil, errors.New("No file list available for: " + nick)
  }
  return list.FindDir(dir)
}

func (c *Client) Download(nick string, pathname string) error {
  extra, _ := path.Split(pathname)
  c.Lock()
  list := c.lists[nick]
  c.Unlock()
  if list == nil {
    return errors.New("No file list available for: " + nick)
  }
  return list.EachFile(pathname, func(f *File, path string) error {
    dl := NewDownloadFile(nick, path, f)
    dl.reldst = path[len(extra):]
    return c.download(dl)
  })
}

func (c *Client) Stop() {
  c.DisconnectHub()
  c.shares.halt()
  peers := make([]*peer, 0)
  c.Lock()
  for _, peer := range c.peers {
    if peer == nil { continue }
    if peer.in != nil {
      peer.in.Close()
      if peer.out != nil {
        peer.out.Close()
        peers = append(peers, peer)
      }
    }
  }
  c.Unlock()

  for _, p := range peers {
    <-p.dead
  }
}

func (c *Client) Say(msg string) {
  if c.Hub.write != nil {
    fmt.Fprintf(c.Hub.write, "<%s> %s|", c.Nick, msg)
    c.Hub.write.Flush()
  }
}

func (c *Client) Info(nick string) *NickInfo {
  c.Lock()
  defer c.Unlock()
  return c.Hub.nicks[nick]
}
