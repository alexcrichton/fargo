package dc

import "bufio"
import "bytes"
import "compress/zlib"
import "io"
import "io/ioutil"
import "os"
import "testing"

func getcmd(t *testing.T, in *bufio.Reader, cmd string, m *method) {
  err := readCmd(in, m)
  if err != nil { t.Fatal(err) }
  if m.name != cmd {
    t.Fatal("Expected '" + cmd + "' got '" + m.name + "'")
  }
}

func xsend(t *testing.T, out *bufio.Writer, data string) {
  _, err := out.WriteString(data)
  if err == nil {
    err = out.Flush()
  }
  if err != nil {
    t.Fatal("Error sending '" + data + "' : " + err.Error())
  }
}

func zsend(t *testing.T, out *bufio.Writer, data string) {
  writer := zlib.NewWriter(out)
  _, err := writer.Write([]byte(data))
  if err == nil {
    err = writer.Flush()
    if err == nil {
      err = out.Flush()
    }
  }
  if err != nil {
    t.Fatal("Error sending '" + data + "' : " + err.Error())
  }
}

func tmpdir(t *testing.T) string {
  wd := os.TempDir()
  wd, err := ioutil.TempDir(wd, "fargo")
  if err != nil { t.Fatal(err) }
  return wd
}

func setupPeer(t *testing.T) (*Client, *bufio.Reader, *bufio.Writer) {
  c := NewClient()
  c.Nick = "foo"
  c.DL.Cnt = 1
  c.UL.Cnt = 1
  c.DownloadRoot = tmpdir(t)

  _in, peerout := io.Pipe()
  peerin, _out := io.Pipe()

  go func() {
    err := c.handlePeer(peerin, peerout)
    peerin.Close()
    peerout.Close()
    if err != nil { t.Fatal(err) }
  }()
  return c, bufio.NewReader(_in), bufio.NewWriter(_out)
}

func handshake(t *testing.T, in *bufio.Reader, out *bufio.Writer,
               supports string) {
  var m method
  xsend(t, out, "$MyNick bar|$Lock foo a|")

  getcmd(t, in, "MyNick", &m)
  if string(m.data) != "foo" { t.Error(string(m.data)) }

  getcmd(t, in, "Lock", &m)
  lockdata := m.data
  idx := bytes.IndexByte(m.data, ' ')
  getcmd(t, in, "Supports", &m)
  getcmd(t, in, "Direction", &m)
  getcmd(t, in, "Key", &m)

  if supports != "" {
    xsend(t, out, "$Supports " + supports + "|")
  }
  xsend(t, out, "$Direction Download|$Key ")
  xsend(t, out, string(GenerateKey(lockdata[0:idx])))
  xsend(t, out, "|")
}

/* Old school ancient way of fetching a file */
func Test_Get(t *testing.T) {
  var m method
  c, in, out := setupPeer(t)
  handshake(t, in, out, "")

  dl := NewDownload("bar", "a b")
  go c.download(dl)

  getcmd(t, in, "Get", &m)
  if string(m.data) != "a b$1" {
    t.Fatal(string(m.data))
  }
  xsend(t, out, "$FileLength 1|")
  getcmd(t, in, "Send", &m)
  xsend(t, out, "f")

  data, err := ioutil.ReadFile(c.DownloadRoot + "/a b")
  if err != nil { t.Fatal(err) }
  if string(data) != "f" { t.Fatal(string(data)) }
}

/* Client supports the non-zlib form of UGetBlock */
func Test_UGetBlock(t *testing.T) {
  var m method
  c, in, out := setupPeer(t)
  handshake(t, in, out, "XmlBZList")

  dl := NewDownload("bar", "a b")
  dl.size = 4
  dl.offset = 1
  go c.download(dl)

  getcmd(t, in, "UGetBlock", &m)
  if string(m.data) != "1 4 a b" {
    t.Fatal(string(m.data))
  }
  xsend(t, out, "$Sending 4|ffff")

  data, err := ioutil.ReadFile(c.DownloadRoot + "/a b")
  if err != nil { t.Fatal(err) }
  if string(data) != "\u0000ffff" { t.Fatal(string(data)) }
}

/* Client supports zlib form of UGetBlock */
func Test_UGetZBlock(t *testing.T) {
  var m method
  c, in, out := setupPeer(t)
  handshake(t, in, out, "GetZBlock")

  dl := NewDownload("bar", "a b")
  dl.size = 5
  dl.offset = 0
  go c.download(dl)

  getcmd(t, in, "UGetZBlock", &m)
  if string(m.data) != "0 5 a b" {
    t.Fatal(string(m.data))
  }
  xsend(t, out, "$Sending 5|")
  zsend(t, out, "fffff")

  data, err := ioutil.ReadFile(c.DownloadRoot + "/a b")
  if err != nil { t.Fatal(err) }
  if string(data) != "fffff" { t.Fatal(string(data)) }
}

/* Client supports ADC, but not with zlib at all */
func Test_ADCSND(t *testing.T) {
  var m method
  c, in, out := setupPeer(t)
  handshake(t, in, out, "ADCGet")

  dl := NewDownload("bar", "a b")
  dl.size = 3
  dl.offset = 1
  go c.download(dl)

  getcmd(t, in, "ADCGET", &m)
  if string(m.data) != "file a b 1 3" {
    t.Fatal(string(m.data))
  }
  xsend(t, out, "$ADCSND file a b 1 3|")
  xsend(t, out, "fff")

  data, err := ioutil.ReadFile(c.DownloadRoot + "/a b")
  if err != nil { t.Fatal(err) }
  if string(data) != "\u0000fff" { t.Fatal(string(data)) }
}

/* Client supports ADC with zlib, but doesn't send with zlib */
func Test_ADCSNDWithZlibButNotCompressed(t *testing.T) {
  var m method
  c, in, out := setupPeer(t)
  handshake(t, in, out, "ADCGet ZLIG")

  dl := NewDownload("bar", "a b")
  dl.size = 2
  dl.offset = 1
  go c.download(dl)

  getcmd(t, in, "ADCGET", &m)
  if string(m.data) != "file a b 1 2 ZL1" {
    t.Fatal(string(m.data))
  }
  xsend(t, out, "$ADCSND file a b 1 2|")
  xsend(t, out, "ff")

  data, err := ioutil.ReadFile(c.DownloadRoot + "/a b")
  if err != nil { t.Fatal(err) }
  if string(data) != "\u0000ff" { t.Fatal(string(data)) }
}

/* Client supports ADC with zlib, and actually sends with zlib */
func Test_ADCSNDWithZlib(t *testing.T) {
  var m method
  c, in, out := setupPeer(t)
  handshake(t, in, out, "ADCGet ZLIG")

  dl := NewDownload("bar", "a b")
  dl.size = 2
  dl.offset = 2
  go c.download(dl)

  getcmd(t, in, "ADCGET", &m)
  if string(m.data) != "file a b 2 2 ZL1" {
    t.Fatal(string(m.data))
  }
  xsend(t, out, "$ADCSND file a b 2 2 ZL1|")
  zsend(t, out, "ff")

  data, err := ioutil.ReadFile(c.DownloadRoot + "/a b")
  if err != nil { t.Fatal(err) }
  if string(data) != "\u0000\u0000ff" { t.Fatal(string(data)) }
}