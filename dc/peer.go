package dc

import "bufio"
import "sync"
import "fmt"
import "os"

type peer struct {
  nick	   string
  write	   *bufio.Writer
  supports []string

  lock	    sync.Mutex
  state	    peerState
  dl	    *download
  outfile   *os.File
}

type peerState int
const (
  Idle = 0
  Downloading = 1
  Uploading peerState = 2
)

func (d *download) fileList() bool {
  return d.file == "files.xml.bz2"
}

func (p *peer) download(dl *download) bool {
  if dl.fileList() {
    if p.implements("XmlBZList") {
      dl.file = "files.xml.bz2"
    } else if p.implements("BZList") {
      dl.file = "MyList.bz2"
    } else {
      return false
    }
  }

  p.lock.Lock()
  if p.state != Idle {
    p.lock.Unlock()
    return false
  }
  p.state = Downloading
  if p.dl != nil { panic("state download") }
  p.dl = dl
  p.lock.Unlock()

  f, err := os.Create("files.xml.bz2")
  if err != nil { panic("couldn't open") }
  p.outfile = f

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
      fmt.Fprintf(w, "%s$%d", dl.file, dl.offset + 1)
    })
  }
  return true
}

func (p *peer) implements(extension string) bool {
  for _, s := range p.supports {
    if extension == s { return true }
  }
  return false
}
