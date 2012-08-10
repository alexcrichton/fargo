package fargo

import "io"
import "sort"
import "strings"
import "testing"

func Test_ParseListing(t *testing.T) {
  list := `
    <?xml version="1.0" encoding="UTF-8"?>
    <FileListing Base="/" Version="1" Generator="fargo"
                 CID="CID">
      <Directory Name="shared">
        <File Name="a" Size="1" TTH="ttha"/>
        <File Name="b" Size="2" TTH="tthb"/>
        <Directory Name="c">
          <File Name="d" Size="3" TTH="tthc"/>
        </Directory>
      </Directory>
    </FileListing>
  `

  var listing FileListing
  err := ParseFileList(strings.NewReader(list), &listing)
  if err != nil { t.Error(err) }

  if listing.Version != "1" { t.Error(listing.Version) }
  if listing.CID != "CID" { t.Error(listing.CID) }
  if listing.Base != "/" { t.Error(listing.Base) }
  if listing.Name != "/" { t.Error(listing.Name) }
  if listing.Generator != "fargo" { t.Error(listing.Generator) }
  if len(listing.Dirs) != 1 { t.Error(len(listing.Dirs)) }
  if len(listing.Files) != 0 { t.Error(len(listing.Files)) }

  d := listing.Dirs[0]
  if d.Name != "shared" { t.Error(d.Name) }
  if len(d.Files) != 2 { t.Error(len(d.Files)) }
  if d.Files[0].Name != "a" { t.Error(d.Files[0].Name) }
  if d.Files[0].Size != ByteSize(1) { t.Error(d.Files[0].Size) }
  if d.Files[0].TTH != "ttha" { t.Error(d.Files[0].TTH) }

  if len(d.Dirs) != 1 { t.Error(len(d.Dirs)) }
  d = d.Dirs[0]
  if d.Name != "c" { t.Error(d.Name) }
  if len(d.Dirs) != 0 { t.Error(len(d.Dirs)) }
  if len(d.Files) != 1 { t.Error(len(d.Files)) }
}

/*
 * Make sure that if the xml says it's utf8, that we do indeed parse it as utf8
 */
func Test_ParseUTF8(t *testing.T) {
  list := "<?xml version='1.0' encoding='UTF-8'?>" +
          "<FileListing CID='£5 for Peppé'></FileListing>"

  var listing FileListing
  err := ParseFileList(strings.NewReader(list), &listing)
  if err != nil { t.Error(err) }
  if listing.CID != "£5 for Peppé" { t.Error(listing.CID) }
}

/*
 * microdc2 can lie by saying that the encoding of the xml is utf-8 but the
 * characters are iso-8859-1 or something similar
 */
func Test_ParseNonUTF8WhenLying(t *testing.T) {
  list := "<?xml version='1.0' encoding='UTF-8'?>" +
          "<FileListing CID='\xa35 for Pepp\xe9'></FileListing>"

  var listing FileListing
  err := ParseFileList(strings.NewReader(list), &listing)
  if err != nil { t.Error(err) }
  if listing.CID != "£5 for Peppé" { t.Error() }
}

func dummy() *FileListing {
  var listing FileListing
  listing.Files = make([]File, 4)
  listing.Dirs = make([]Directory, 2)

  listing.Files[0] = File{Name: "foo"}
  listing.Files[1] = File{Name: "bar"}
  listing.Files[2] = File{Name: "a"}
  listing.Files[3] = File{Name: "z"}
  listing.Dirs[0] = Directory{Name: "foo"}
  listing.Dirs[1] = Directory{Name: "bar"}
  return &listing
}

func Test_Sorting(t *testing.T) {
  listing := dummy()
  sort.Sort(listing)

  if listing.Dirs[0].Name != "bar" { t.Error() }
  if listing.Dirs[1].Name != "foo" { t.Error() }
  if listing.Files[0].Name != "a" { t.Error() }
  if listing.Files[1].Name != "bar" { t.Error() }
  if listing.Files[2].Name != "foo" { t.Error() }
  if listing.Files[3].Name != "z" { t.Error() }
}

func Test_Encode(t *testing.T) {
  listing := dummy()

  var listing2 FileListing
  read, write := io.Pipe()
  go func() {
    err := EncodeFileList(listing, write)
    if err != nil { t.Error(err) }
    write.Close()
  }()
  err := ParseFileList(read, &listing2)
  if err != nil { t.Error(err) }

  if len(listing2.Files) != 4 { t.Error() }
  if len(listing2.Dirs) != 2 { t.Error() }
}

func Test_Visiting(t *testing.T) {
  listing := dummy()
  sort.Sort(listing)
  listing.Dirs[0].Files = []File{ File{Name: "foo"} }

  /* visit all files */
  visited := 0
  err := listing.EachFile("/", func(f *File, path string) error {
    switch visited {
      case 0: if path != "/a" { t.Error(path) }
      case 1: if path != "/bar" { t.Error(path) }
      case 2: if path != "/foo" { t.Error(path) }
      case 3: if path != "/z" { t.Error(path) }
      case 4: if path != "/bar/foo" { t.Error(path) }
    }
    visited++
    return nil
  })
  if err != nil { t.Error(err) }
  if visited != 5 { t.Error(visited) }

  /* visit a root file */
  visited = 0
  err = listing.EachFile("/a", func(f *File, path string) error {
    if visited > 0 { t.Error(path) }
    visited++
    if path != "/a" { t.Error(path) }
    return nil
  })
  if err != nil { t.Error(err) }
  if visited != 1 { t.Error(visited) }

  /* visit a directory */
  visited = 0
  err = listing.EachFile("/bar", func(f *File, path string) error {
    if visited > 0 { t.Error(path) }
    visited++
    if path != "/bar/foo" { t.Error(path) }
    return nil
  })
  if err != nil { t.Error(err) }
  if visited != 1 { t.Error(visited) }

  /* visit a file in a directory */
  visited = 0
  err = listing.EachFile("/bar/foo", func(f *File, path string) error {
    if visited > 0 { t.Error(path) }
    visited++
    if path != "/bar/foo" { t.Error(path) }
    return nil
  })
  if err != nil { t.Error(err) }
  if visited != 1 { t.Error(visited) }
}
