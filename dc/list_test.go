package dc

import "testing"
import "strings"

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
  ParseFileList(strings.NewReader(list), &listing)

  if listing.Version != "1" {
    t.Errorf("Wrong version: %s", listing.Version)
  }
  if listing.CID != "CID" {
    t.Errorf("Wrong cid: %s", listing.CID)
  }
  if listing.Base != "/" {
    t.Errorf("Wrong base: %s", listing.Base)
  }
  if listing.Generator != "fargo" {
    t.Errorf("Wrong generator: %s", listing.Generator)
  }

  if len(listing.Directory) != 1 {
    t.Error("wrong number of directories")
  }
  if len(listing.File) != 0 {
    t.Error("wrong number of files")
  }
  d := listing.Directory[0]
  if d.Name != "shared" {
    t.Errorf("wrong directory name")
  }
  if len(d.File) != 2 {
    t.Error("wrong number of files")
  }
  if d.File[0].Name != "a" {
    t.Error("wrong filename")
  }
  if d.File[0].Size != "1" {
    t.Error("wrong size")
  }
  if d.File[0].TTH != "ttha" {
    t.Error("wrong tth")
  }

  if len(d.Directory) != 1 {
    t.Error("wrong number of directories")
  }
  d = d.Directory[0]
  if d.Name != "c" {
    t.Error("wrong name")
  }
  if len(d.Directory) != 0 {
    t.Error("wrong number")
  }
  if len(d.File) != 1 {
    t.Error("wrong number")
  }
}
