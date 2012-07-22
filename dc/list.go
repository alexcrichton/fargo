package dc

import "fmt"
import "io"
import "encoding/xml"
import "code.google.com/p/go-charset/charset"
import _ "code.google.com/p/go-charset/data"

type FileListing struct {
  Version   string `xml:",attr"`
  Base      string `xml:",attr"`
  Generator string `xml:",attr"`
  CID       string `xml:",attr"`

  Directory
}

type Directory struct {
  Name string `xml:",attr"`

  Dirs  []Directory `xml:"Directory"`
  Files []File      `xml:"File"`
}

type File struct {
  Name string   `xml:",attr"`
  Size ByteSize `xml:",attr"`
  TTH  string   `xml:",attr"`
}

func (d *Directory) Len() int {
  return len(d.Dirs) + len(d.Files)
}

func (d *Directory) Less(i, j int) bool {
  dirs := len(d.Dirs)
  if i < dirs {
    if j >= dirs {
      return true
    } else {
      return d.Dirs[i].Name < d.Dirs[j].Name
    }
  }
  if j < dirs { return false }
  return d.Files[i - dirs].Name < d.Files[j - dirs].Name
}

func (d *Directory) Swap(i, j int) {
  dirs := len(d.Dirs)
  if i < dirs {
    if j >= dirs { return }
    d.Dirs[i], d.Dirs[j] = d.Dirs[j], d.Dirs[i]
  } else {
    if j < dirs { return }
    d.Files[i - dirs], d.Files[j - dirs] = d.Files[j - dirs], d.Files[i - dirs]
  }
}

func ParseFileList(in io.Reader, out *FileListing) (err error) {
  in, err = charset.NewReader("iso-8859-1", in)
  if err != nil { return }
  decoder := xml.NewDecoder(in)
  err = decoder.Decode(out)
  out.Name = out.Base
  return
}

type ByteSize float64

const (
  _           = iota // ignore first value by assigning to blank identifier
  KB ByteSize = 1 << (10 * iota)
  MB
  GB
  TB
)

func (b ByteSize) String() string {
  switch {
  case b >= TB:
    return fmt.Sprintf("%.2fTB", b/TB)
  case b >= GB:
    return fmt.Sprintf("%.2fGB", b/GB)
  case b >= MB:
    return fmt.Sprintf("%.2fMB", b/MB)
  case b >= KB:
    return fmt.Sprintf("%.2fKB", b/KB)
  }
  return fmt.Sprintf("%.2fB", b)
}
