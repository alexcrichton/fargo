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

func xread(t *testing.T, in io.Reader, n int, z bool) string {
  bytes := make([]byte, n)
  var err error

  if z {
    in, err = zlib.NewReader(in)
    if err != nil { t.Fatal(err) }
  }
  _, err = io.ReadAtLeast(in, bytes, n)
  if err != nil { t.Fatal(err) }
  return string(bytes)
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

func stub_file(t *testing.T, c *Client) {
  c.CacheDir = c.DownloadRoot
  c.SpawnHashers()
  root := c.DownloadRoot + "/share"
  err := os.Mkdir(root, os.FileMode(0755))
  if err != nil { t.Fatal(err) }
  err = ioutil.WriteFile(root + "/a b", []byte("abcd"), os.FileMode(0644))
  if err != nil { t.Fatal(err) }
  c.Share("foo", root)
}

func tmpdir(t *testing.T) string {
  wd := os.TempDir()
  wd, err := ioutil.TempDir(wd, "fargo")
  if err != nil { t.Fatal(err) }
  return wd
}

func setupPeer(t *testing.T) (*Client, *bufio.Reader, *bufio.Writer,
                              *io.PipeReader, *io.PipeWriter) {
  c := NewClient()
  c.Nick = "foo"
  c.DL.Cnt = 1
  c.UL.Cnt = 1
  c.DownloadRoot = tmpdir(t)

  _in, peerout := io.Pipe()
  peerin, _out := io.Pipe()

  go func() {
    err := c.handlePeer(peerin, peerout, false)
    peerin.Close()
    peerout.Close()
    if err != nil && err != io.EOF { t.Fatal(err) }
  }()
  stub_file(t, c)
  return c, bufio.NewReader(_in), bufio.NewWriter(_out), _in, _out
}

func teardownPeer(t *testing.T, c *Client,
                  in *io.PipeReader, out *io.PipeWriter) {
  // in.Close()
  out.Close()
  c.shares.halt()
  os.RemoveAll(c.DownloadRoot)
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
  c, in, out, _in, _out := setupPeer(t)
  defer teardownPeer(t, c, _in, _out)
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
  c, in, out, _in, _out := setupPeer(t)
  defer teardownPeer(t, c, _in, _out)
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
  c, in, out, _in, _out := setupPeer(t)
  defer teardownPeer(t, c, _in, _out)
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
  c, in, out, _in, _out := setupPeer(t)
  defer teardownPeer(t, c, _in, _out)
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
  c, in, out, _in, _out := setupPeer(t)
  defer teardownPeer(t, c, _in, _out)
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
  c, in, out, _in, _out := setupPeer(t)
  defer teardownPeer(t, c, _in, _out)
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

/* Test old-school form of uploading */
func Test_Send(t *testing.T) {
  var m method
  c, in, out, _in, _out := setupPeer(t)
  defer teardownPeer(t, c, _in, _out)
  handshake(t, in, out, "")

  xsend(t, out, "$Get foo/a b$2|")
  getcmd(t, in, "FileLength", &m)
  if string(m.data) != "3" {
    t.Fatal(string(m.data))
  }
  xsend(t, out, "$Send|")

  data := xread(t, in, 3, false)
  if data != "bcd" { t.Fatal(data) }
}

/* UGetBlock uploading half */
func Test_UploadViaUGetBlock(t *testing.T) {
  var m method
  c, in, out, _in, _out := setupPeer(t)
  defer teardownPeer(t, c, _in, _out)
  handshake(t, in, out, "")

  xsend(t, out, "$UGetBlock 1 2 foo/a b|")
  getcmd(t, in, "Sending", &m)
  if string(m.data) != "2" { t.Fatal(string(m.data)) }

  data := xread(t, in, 2, false)
  if data != "bc" { t.Fatal(data) }
}

/* UGetZBlock uploading half */
func Test_UploadViaUGetZBlock(t *testing.T) {
  var m method
  c, in, out, _in, _out := setupPeer(t)
  defer teardownPeer(t, c, _in, _out)
  handshake(t, in, out, "")

  xsend(t, out, "$UGetZBlock 1 10 foo/a b|")
  getcmd(t, in, "Sending", &m)
  if string(m.data) != "3" { t.Fatal(string(m.data)) }

  data := xread(t, in, 3, true)
  if data != "bcd" { t.Fatal(data) }
}

/* ADCSND upload without zlib */
func Test_UploadViaADCNoZlib(t *testing.T) {
  var m method
  c, in, out, _in, _out := setupPeer(t)
  defer teardownPeer(t, c, _in, _out)
  handshake(t, in, out, "")

  xsend(t, out, "$ADCGET file foo/a b 2 1|")
  getcmd(t, in, "ADCSND", &m)
  if string(m.data) != "file foo/a b 2 1" { t.Fatal(string(m.data)) }

  data := xread(t, in, 1, false)
  if data != "c" { t.Fatal(data) }
}

/* ADCSND upload with zlib */
func Test_UploadViaADCWithZlib(t *testing.T) {
  var m method
  c, in, out, _in, _out := setupPeer(t)
  defer teardownPeer(t, c, _in, _out)
  handshake(t, in, out, "")

  xsend(t, out, "$ADCGET file foo/a b 3 100 ZL1|")
  getcmd(t, in, "ADCSND", &m)
  if string(m.data) != "file foo/a b 3 1 ZL1" { t.Fatal(string(m.data)) }

  data := xread(t, in, 1, true)
  if data != "d" { t.Fatal(data) }
}

/* ADCSND with a size as -1 (known bug before) */
func Test_UploadViaADCWithNegativeSize(t *testing.T) {
  var m method
  c, in, out, _in, _out := setupPeer(t)
  defer teardownPeer(t, c, _in, _out)
  handshake(t, in, out, "")

  xsend(t, out, "$ADCGET file foo/a b 3 -1 ZL1|")
  getcmd(t, in, "ADCSND", &m)
  if string(m.data) != "file foo/a b 3 1 ZL1" { t.Fatal(string(m.data)) }

  data := xread(t, in, 1, true)
  if data != "d" { t.Fatal(data) }
}

/* ADCSND where file is identified with a TTH */
func Test_UploadViaADCWithTTH(t *testing.T) {
  var m method
  c, in, out, _in, _out := setupPeer(t)
  defer teardownPeer(t, c, _in, _out)
  handshake(t, in, out, "")
  c.shares.queryWait("foo") /* wait for tth hashes to propogate */

  tth := "SQF2PFTVIFRR5KJSI45IDENXMB43NI7EIXYGHGI"
  xsend(t, out, "$ADCGET tthl TTH/" + tth + " 0 -1|")
  getcmd(t, in, "ADCSND", &m)
  if string(m.data) != "tthl TTH/" + tth + " 0 4" {
    t.Fatal(string(m.data))
  }
  data := xread(t, in, 4, false)
  if data != "abcd" { t.Fatal(data) }
}

/* Test MiniSlots support */
func Test_SupportsMiniSlots(t *testing.T) {
  var m method
  c, in, out, _in, _out := setupPeer(t)
  defer teardownPeer(t, c, _in, _out)
  handshake(t, in, out, "")

  if c.UL.Cnt != 1 { t.Fatal(c.UL.Cnt) }
  xsend(t, out, "$ADCGET file files.xml.bz2 0 -1|")
  getcmd(t, in, "ADCSND", &m)
  if c.UL.Cnt != 1 { t.Fatal(c.UL.Cnt) }
}

/* Test slots are actually taken for uploads */
func Test_SupportsUploadSlots(t *testing.T) {
  var m method
  c, in, out, _in, _out := setupPeer(t)
  defer teardownPeer(t, c, _in, _out)
  handshake(t, in, out, "")

  if c.UL.Cnt != 1 { t.Fatal(c.UL.Cnt) }
  xsend(t, out, "$ADCGET file foo/a b 0 -1|")
  getcmd(t, in, "ADCSND", &m)
  if c.UL.Cnt != 0 { t.Fatal(c.UL.Cnt) }
  xread(t, in, 4, false)

  xsend(t, out, "$") /* wait for the peer to get back around to reading data */
  if c.UL.Cnt != 1 { t.Fatal(c.UL.Cnt) }
}

/* Test slots are actually taken for downloads */
func Test_SupportsDownloadSlots(t *testing.T) {
  var m method
  c, in, out, _in, _out := setupPeer(t)
  defer teardownPeer(t, c, _in, _out)
  handshake(t, in, out, "ADCGet")

  if c.DL.Cnt != 1 { t.Fatal(c.DL.Cnt) }
  dl := NewDownload("bar", "a b")
  go c.download(dl)

  getcmd(t, in, "ADCGET", &m)
  if c.DL.Cnt != 0 { t.Fatal(c.DL.Cnt) }
  xsend(t, out, "$ADCSND file a b 0 3|")
  xsend(t, out, "fff")

  xsend(t, out, "$")
  if c.DL.Cnt != 1 { t.Fatal(c.DL.Cnt) }
}
