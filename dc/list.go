package dc

import "io"
import "encoding/xml"
import "code.google.com/p/go-charset/charset"
import _ "code.google.com/p/go-charset/data"

import "../glue"

type FileListing struct {
  Version   string `xml:",attr"`
  Base      string `xml:",attr"`
  Generator string `xml:",attr"`
  CID       string `xml:",attr"`

  Dirs  []Directory `xml:"Directory"`
  Files []File      `xml:"File"`
}

type Directory struct {
  XName string `xml:"Name,attr"`

  Dirs  []Directory `xml:"Directory"`
  Files []File      `xml:"File"`
}

type File struct {
  XName string `xml:"Name,attr"`
  XSize uint64 `xml:"Size,attr"`
  XTTH  string `xml:"TTH,attr"`
}

/* Implementation of sort.Interface for glue.Directory */
func slen(d []Directory, f []File) int {
  return len(d) + len(f)
}

func less(d []Directory, f[]File, i, j int) bool {
  dirs := len(d)
  if i < dirs {
    if j >= dirs {
      return true
    } else {
      return d[i].XName < d[j].XName
    }
  }
  if j < dirs {
    return false
  }
  return f[i - dirs].XName < f[j - dirs].XName
}

func swap(d []Directory, f []File, i, j int) {
  dirs := len(d)
  if i < dirs {
    if j >= dirs {
      panic("bad idx")
    }
    tmp := d[i]
    d[i] = d[j]
    d[j] = tmp
  } else {
    if j < dirs {
      panic("bad idx")
    }
    tmp := f[i - dirs]
    f[i - dirs] = f[j - dirs]
    f[j - dirs] = tmp
  }
}

/* Implementation of the glue.Directory interface */
func (f *FileListing) DirectoryCount() int            { return len(f.Dirs) }
func (f *FileListing) Directory(i int) glue.Directory { return &f.Dirs[i] }
func (f *FileListing) FileCount() int                 { return len(f.Files) }
func (f *FileListing) File(i int) glue.File           { return &f.Files[i] }
func (f *FileListing) Name() string                   { return "/" }
func (f *FileListing) Len() int           { return slen(f.Dirs, f.Files) }
func (f *FileListing) Less(i, j int) bool { return less(f.Dirs, f.Files, i, j) }
func (f *FileListing) Swap(i, j int)      { swap(f.Dirs, f.Files, i, j) }

func (d *Directory) DirectoryCount() int            { return len(d.Dirs) }
func (d *Directory) Directory(i int) glue.Directory { return &d.Dirs[i] }
func (d *Directory) FileCount() int                 { return len(d.Files) }
func (d *Directory) File(i int) glue.File           { return &d.Files[i] }
func (d *Directory) Name() string                   { return d.XName }
func (d *Directory) Len() int           { return slen(d.Dirs, d.Files) }
func (d *Directory) Less(i, j int) bool { return less(d.Dirs, d.Files, i, j) }
func (d *Directory) Swap(i, j int)      { swap(d.Dirs, d.Files, i, j) }

/* Implementation of the glue.File interface */
func (f *File) Name() string        { return f.XName }
func (f *File) Size() glue.ByteSize { return glue.ByteSize(f.XSize) }
func (f *File) TTH() string         { return f.XTTH }

func ParseFileList(in io.Reader, out *FileListing) (err error) {
  in, err = charset.NewReader("iso-8859-1", in)
  if err != nil {
    return
  }
  decoder := xml.NewDecoder(in)
  return decoder.Decode(out)
}
