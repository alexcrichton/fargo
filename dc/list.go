package dc

import "encoding/xml"
import "fmt"
import "io"
import "io/ioutil"

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
  Name string `xml:",attr,omitempty"`

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
  defer func() { out.Name = out.Base }()
  data, err := ioutil.ReadAll(in)
  if err != nil { return }

  /* First, try just reading it */
  err = xml.Unmarshal(data, out)
  if err == nil { return }

  /* If that failed, then try to read in another charset. This happens because
   * microdc2 is known to lie by saying that the content is utf-8 when it's
   * actually iso-8859-1 */
  translator, err := charset.TranslatorFrom("iso-8859-1")
  if err != nil { return }
  _, data, err = translator.Translate(data, true)
  if err != nil { return }
  return xml.Unmarshal(data, out)
}

func EncodeFileList(in *FileListing, out io.Writer) (err error) {
  _, err = out.Write([]byte(xml.Header))
  if err != nil { return }
  encoder := xml.NewEncoder(out)
  return encoder.Encode(in)
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
