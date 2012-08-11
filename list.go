package fargo

import "encoding/xml"
import "errors"
import "fmt"
import "io"
import "io/ioutil"
import "path"
import "strings"
import "time"

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

  realpath string
  version  uint64
}

type File struct {
  Name string   `xml:",attr"`
  Size ByteSize `xml:",attr"`
  TTH  string   `xml:",attr"`

  mtime    time.Time
  version  uint64
  realpath string
}

type VisitFunc func(*File, string) error

var FileNotFound = errors.New("File not found")
var DirectoryNotFound = errors.New("Directory not found")

func NewDirectory(name string, path string) Directory {
  return Directory{Name: name,
                   realpath: path,
                   Dirs: make([]Directory, 0),
                   Files: make([]File, 0)}
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

func (f *FileListing) FindDir(dir string) (*Directory, error) {
  if dir == "" || dir == "/" { return &f.Directory, nil }

  parts := strings.Split(dir, "/")
  if path.IsAbs(dir) {
    parts = parts[1:]
  }
  cur := &f.Directory
  for _, subdir := range parts {
    found := false
    for i, child := range cur.Dirs {
      if child.Name == subdir {
        found = true
        cur = &cur.Dirs[i]
        break
      }
    }
    if !found {
      return nil, errors.New(dir + " is not a directory")
    }
  }
  return cur, nil
}

func (f *FileListing) FindFile(pathname string) (file *File, err error) {
  dirname, base := path.Split(pathname)
  dir, err := f.FindDir(dirname[0:len(dirname)-1])
  if err != nil { return }
  for i, f := range dir.Files {
    if f.Name == base { return &dir.Files[i], nil }
  }
  return nil, FileNotFound
}

func (d *Directory) visit(pathname string, cb VisitFunc) error {
  for i, file := range d.Files {
    err := cb(&d.Files[i], path.Join(pathname, file.Name))
    if err != nil { return err }
  }
  for _, dir := range d.Dirs {
    err := dir.visit(path.Join(pathname, dir.Name), cb)
    if err != nil { return err }
  }
  return nil
}

func (d *Directory) childFile(name string) *File {
  for i, file := range d.Files {
    if file.Name == name { return &d.Files[i] }
  }
  return nil
}

func (d *Directory) childDir(name string) *Directory {
  for i, dir := range d.Dirs {
    if dir.Name == name { return &d.Dirs[i] }
  }
  return nil
}

func (d *Directory) removeDir(i int) {
  back := len(d.Dirs) - 1
  if i < back {
    d.Dirs[i] = d.Dirs[back]
  }
  d.Dirs = d.Dirs[0:back]
}

func (d *Directory) removeDirName(name string) {
  for i, dir := range d.Dirs {
    if dir.Name == name {
      d.removeDir(i)
      break
    }
  }
}

func (d *Directory) removeFileName(name string) {
  for i, file := range d.Files {
    if file.Name == name {
      d.removeFile(i)
      break
    }
  }
}

func (d *Directory) removeFile(i int) {
  back := len(d.Files) - 1
  if i < back {
    d.Files[i] = d.Files[back]
  }
  d.Files = d.Files[0:back]
}

func (f *FileListing) EachFile(path string, cb VisitFunc) error {
  dir, err := f.FindDir(path)
  if err == nil {
    return dir.visit(path, cb)
  }
  file, err := f.FindFile(path)
  if err == nil {
    return cb(file, path)
  }
  return err
}

type ByteSize uint64

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
