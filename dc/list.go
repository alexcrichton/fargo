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

func (f *FileListing) DirectoryCount() int            { return len(f.Dirs) }
func (f *FileListing) Directory(i int) glue.Directory { return &f.Dirs[i] }
func (f *FileListing) FileCount() int                 { return len(f.Files) }
func (f *FileListing) File(i int) glue.File           { return &f.Files[i] }
func (f *FileListing) Name() string                   { return "/" }

func (d *Directory) DirectoryCount() int            { return len(d.Dirs) }
func (d *Directory) Directory(i int) glue.Directory { return &d.Dirs[i] }
func (d *Directory) FileCount() int                 { return len(d.Files) }
func (d *Directory) File(i int) glue.File           { return &d.Files[i] }
func (d *Directory) Name() string                   { return d.XName }

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
