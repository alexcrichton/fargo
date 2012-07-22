package dc

import "testing"
import "strings"
import "sort"

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
  if err != nil {
    t.Error(err)
  }

  if listing.Version != "1" {
    t.Errorf("Wrong version: %s", listing.Version)
  }
  if listing.CID != "CID" {
    t.Errorf("Wrong cid: %s", listing.CID)
  }
  if listing.Base != "/" {
    t.Errorf("Wrong base: %s", listing.Base)
  }
  if listing.Name != "/" {
    t.Errorf("Wrong name: %s", listing.Name)
  }
  if listing.Generator != "fargo" {
    t.Errorf("Wrong generator: %s", listing.Generator)
  }

  if len(listing.Dirs) != 1 {
    t.Error("wrong number of directories")
  }
  if len(listing.Files) != 0 {
    t.Error("wrong number of files")
  }
  d := listing.Dirs[0]
  if d.Name != "shared" {
    t.Errorf("wrong directory name")
  }
  if len(d.Files) != 2 {
    t.Error("wrong number of files")
  }
  if d.Files[0].Name != "a" {
    t.Error("wrong filename")
  }
  if d.Files[0].Size != ByteSize(1) {
    t.Error("wrong size")
  }
  if d.Files[0].TTH != "ttha" {
    t.Error("wrong tth")
  }

  if len(d.Dirs) != 1 {
    t.Error("wrong number of directories")
  }
  d = d.Dirs[0]
  if d.Name != "c" {
    t.Error("wrong name")
  }
  if len(d.Dirs) != 0 {
    t.Error("wrong number")
  }
  if len(d.Files) != 1 {
    t.Error("wrong number")
  }
}

/**
 * microdc2 can lie by saying that the encoding of the xml is utf-8 but the
 * characters are iso-8859-1 or something similar
 */
func Test_ParseNonUTF8(t *testing.T) {
  list := "<?xml version='1.0' encoding='UTF-8'?>" +
          "<FileListing Base='/' Version='1' Generator='fargo'" +
                       "CID='\xa35 for Pepp\xe9'>" +
          "</FileListing>"

  var listing FileListing
  err := ParseFileList(strings.NewReader(list), &listing)
  if err != nil {
    t.Error(err)
  }
  if listing.CID != "£5 for Peppé" {
    t.Error("Couldn't parse")
  }
}

func Test_Sorting(t *testing.T) {
  var listing FileListing
  listing.Files = make([]File, 4)
  listing.Dirs = make([]Directory, 2)

  listing.Files[0] = File{Name: "foo"}
  listing.Files[1] = File{Name: "bar"}
  listing.Files[2] = File{Name: "a"}
  listing.Files[3] = File{Name: "z"}
  listing.Dirs[0] = Directory{Name: "foo"}
  listing.Dirs[1] = Directory{Name: "bar"}

  sort.Sort(&listing) // don't panic
}
