package dc

import "bufio"
import "bytes"
import "errors"
import "fmt"
import "net"
import "path"
import "strings"
import "sync"

import "../glue"

type Client struct {
  /* configuration options */
  HubAddress    string
  ClientAddress string
  Nick          string
  Passive       bool
  DL            Slots
  UL            Slots
  DownloadRoot  string

  logc   chan string
  peers  map[string]*peer
  dls    map[string][]*download
  failed []*download
  hub    hubConn

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

type hubConn struct {
  conn  net.Conn
  write *bufio.Writer
  name  string
  nicks []string
  ops   []string
}

type method struct {
  name string
  data []byte
}

var notConnected = errors.New("not connected to the hub")

func NewClient() *Client {
  return &Client{Passive: true,
    peers: make(map[string]*peer),
    dls: make(map[string][]*download),
    failed: make([]*download, 0),
    hub: hubConn{nicks: make([]string, 0), ops: make([]string, 0)}}
}

func (c *Client) log(msg string) {
  c.logc <- msg
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
      panic(err)
    }
    go func() {
      for {
        conn, err := ln.Accept()
        if err != nil {
          break
        }
        go c.readPeer(conn)
      }
      c.log("Active server shut down")
    }()
    defer ln.Close()
  }

  /* Create the tcp connection to the hub */
  conn, err := net.Dial("tcp", c.HubAddress)
  if err != nil {
    c.log("error connecting: " + err.Error())
    return
  }
  if c.hub.conn != nil {
    panic("already have hub connection")
  }
  c.hub.conn = conn
  c.hub.write = bufio.NewWriter(conn)
  defer func() {
    c.hub.conn = nil
    c.hub.write = nil
  }()
  hub := bufio.NewReader(conn)
  var m method
  defer c.log("Hub disconnected")

  /* Step 1 - Receive the hub's lock */
  if readCmd(hub, &m) != nil {
    return
  }
  if m.name != "Lock" {
    return
  }
  idx := bytes.IndexByte(m.data, ' ')
  if idx == -1 {
    return
  }

  /* Step 2 - Receive the hub's name */
  if readCmd(hub, &m) != nil {
    return
  }
  if m.name != "HubName" {
    return
  }
  c.log("Connected to hub: " + string(m.data))

  /* Step 3 - send our credentials */
  send(c.hub.write, "Key", GenerateKey(m.data[0:idx]))
  send(c.hub.write, "ValidateNick", []byte(c.Nick))

  /* Step 4 - receive our $Hello and reply with our info */
  if readCmd(hub, &m) != nil {
    return
  }
  if m.name != "Hello" {
    return
  }
  if string(m.data) != c.Nick {
    return
  }
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
                b, c.UL.Cnt)
    /* $speed\001$email$size$ */
    /* TODO: real file size */
    w.WriteString("$ $DSL\001$$5368709121$")
  })
  send(c.hub.write, "GetNickList", nil)

  /* Step 4+ - process commands from the hub as they're received */
  for {
    cmd, err := hub.ReadBytes('|')
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
    snicks := make([]string, 0)
    for _, name := range nicks {
      if len(name) > 0 {
        snicks = append(snicks, string(name))
      }
    }
    c.hub.nicks = snicks

  case "OpList":
    ops := bytes.Split(m.data, []byte("$$"))
    sops := make([]string, 0)
    for _, name := range ops {
      if len(name) > 0 {
        sops = append(sops, string(name))
      }
    }
    c.hub.ops = sops

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
  sendf(c.hub.write, "RevConnectToMe", func(w *bufio.Writer) {
    w.WriteString(c.Nick)
    w.WriteByte(' ')
    w.WriteString(nick)
  })
}

func (c *Client) connect(nick string) {
  sendf(c.hub.write, "ConnectToMe", func(w *bufio.Writer) {
    w.WriteString(nick)
    w.WriteByte(' ')
    w.WriteString(c.ClientAddress)
  })
}

func (c *Client) Browse(nick string) error {
  if c.hub.write == nil {
    return notConnected
  }
  return c.download(NewDownload(nick, FileList))
}

func (c *Client) Nicks() ([]string, error) {
  return c.hub.nicks, nil
}

func (c *Client) Ops() ([]string, error) {
  return c.hub.ops, nil
}

func (c *Client) ConnectHub(msgs chan string) error {
  if c.Nick == "" { return errors.New("no nick is configured") }
  if c.HubAddress == "" { return errors.New("no hub address is configured") }
  if c.DownloadRoot == "" { return errors.New("no download root is configured")}
  if !c.Passive && c.ClientAddress == "" {
    return errors.New("no client address is configured")
  }
  if c.hub.write == nil {
    c.logc = msgs
    go c.run()
    return nil
  }
  return errors.New("already connected to the hub")
}

func (c *Client) DisconnectHub() error {
  if c.hub.conn == nil {
    return notConnected
  }
  c.hub.conn.Close()
  return nil
}

func down(path string, cur glue.Directory) (glue.Directory, error) {
  if path == "/" {
    return cur, nil
  }
  for _, subdir := range strings.Split(path, "/")[1:] {
    found := false
    for i := 0; i < cur.DirectoryCount(); i++ {
      child := cur.Directory(i)
      if child.Name() == subdir {
        found = true
        cur = child
        break
      }
    }
    if !found {
      return nil, errors.New(path + " is not a directory")
    }
  }
  return cur, nil
}

func (c *Client) Listings(nick string, dir string) (glue.Directory, error) {
  p := c.peer(nick, func(*peer) {})

  if p.files == nil {
    return nil, errors.New("No file list available for: " + nick)
  }
  return down(dir, p.files)
}

func (c *Client) dlFiles(nick string, trim string, pathname string,
                         dir glue.Directory) error {
  for i := 0; i < dir.FileCount(); i++ {
    file := dir.File(i)
    fullpath := path.Join(pathname, file.Name())
    dl := NewDownloadFile(nick, fullpath, file)
    dl.reldst = strings.Replace(fullpath, trim, "", 1)
    err := c.download(dl)
    if err != nil { return err }
  }

  for i := 0; i < dir.DirectoryCount(); i++ {
    d := dir.Directory(i)
    err := c.dlFiles(nick, trim, path.Join(pathname, d.Name()), d)
    if err != nil { return err }
  }

  return nil
}

func (c *Client) Download(nick string, pathname string) error {
  p := c.peer(nick, func(*peer) {})
  if p.files == nil {
    return errors.New("No file list available for: " + nick)
  }
  dir, base := path.Split(pathname)
  files, err := down(dir[:len(dir)-1], p.files)
  if err != nil { return err }

  for i := 0; i < files.DirectoryCount(); i++ {
    child := files.Directory(i)
    if child.Name() == base {
      return c.dlFiles(nick, dir, pathname, child)
    }
  }

  for i := 0; i < files.FileCount(); i++ {
    child := files.File(i)
    if child.Name() == base {
      dl := NewDownloadFile(nick, pathname, child)
      dl.reldst = base
      return c.download(dl)
    }
  }
  return errors.New(pathname + " does not exist")
}

func (c *Client) SetHubAddress(addr string) { c.HubAddress = addr }
func (c *Client) SetPassive()               { c.Passive = true }
func (c *Client) SetNick(nick string)       { c.Nick = nick }
func (c *Client) SetDownloadRoot(p string)  { c.DownloadRoot = p }
func (c *Client) SetDLSlots(s int)          { c.DL.Cnt = s }
func (c *Client) SetULSlots(s int)          { c.UL.Cnt = s }
func (c *Client) SetActiveServer(a string)  {
  c.Passive, c.ClientAddress = false, a
}
