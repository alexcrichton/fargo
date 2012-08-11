package fargo

import "testing"
import "io/ioutil"
import "os"
import "path/filepath"

func stub_fs(t *testing.T) {
  err := os.MkdirAll("foo/bar/baz", os.FileMode(0755))
  if err != nil { t.Fatal(err) }
  err = os.MkdirAll("foo/bar2", os.FileMode(0755))
  if err != nil { t.Fatal(err) }
  err = ioutil.WriteFile("foo/a", []byte("a"), os.FileMode(0644))
  if err != nil { t.Fatal(err) }
  err = ioutil.WriteFile("foo/b", []byte("a"), os.FileMode(0644))
  if err != nil { t.Fatal(err) }
  err = ioutil.WriteFile("foo/c", []byte("a"), os.FileMode(0644))
  if err != nil { t.Fatal(err) }
  err = ioutil.WriteFile("foo/bar/a", []byte("a"), os.FileMode(0644))
  if err != nil { t.Fatal(err) }
  err = ioutil.WriteFile("foo/bar/baz/a", []byte("a"), os.FileMode(0644))
  if err != nil { t.Fatal(err) }
  err = ioutil.WriteFile("foo/bar/b", []byte("a"), os.FileMode(0644))
  if err != nil { t.Fatal(err) }
  err = ioutil.WriteFile("foo/bar2/a", []byte("a"), os.FileMode(0644))
  if err != nil { t.Fatal(err) }
  err = ioutil.WriteFile("foo/a b", []byte("a"), os.FileMode(0644))
  if err != nil { t.Fatal(err) }
}

func setup(t *testing.T) (*Shares, string) {
  wd, err := filepath.EvalSymlinks(os.TempDir())
  if err != nil { t.Fatal(err) }
  wd, err = ioutil.TempDir(wd, "fargo")
  if err != nil { t.Fatal(err) }
  err = os.Chdir(wd)
  if err != nil { t.Fatal(err) }

  c := NewClient()
  c.CacheDir = filepath.Join(wd, "cache")
  _shares := NewShares()
  shares := &_shares
  go shares.hash(c)
  stub_fs(t)
  return shares, wd
}

func teardown(s *Shares, wd string) {
  s.halt()
  os.RemoveAll(wd)
}

func Test_ScanShares(t *testing.T) {
  shares, wd := setup(t)
  defer teardown(shares, wd)
  shares.add("name", "foo")

  /* Make sure returned files are valid */
  f := shares.query("name/a")
  if f == nil { t.Fatal() }
  if f.Name != "a" { t.Error(f.Name) }
  if f.realpath != filepath.Join(wd, "foo/a") { t.Error(f.realpath) }
  if f.Size != 1 { t.Error(f.Size) }

  /* query files in various places */
  if shares.query("foo/a") != nil { t.Error() }
  if shares.query("name/bar/a") == nil { t.Error() }
  if shares.query("name/bar/baz/a") == nil { t.Error() }
  if shares.query("name/a b") == nil { t.Error() }
}

func Test_AddRemoveShares(t *testing.T) {
  shares, wd := setup(t)
  defer teardown(shares, wd)
  shares.add("name", filepath.Join(wd, "foo"))

  /* add/remove shares */
  shares.remove("foo")
  if shares.query("name/bar/a") == nil { t.Error() }
  shares.remove("name")
  if shares.query("name/bar/a") != nil { t.Error() }
}

func Test_MultipleShares(t *testing.T) {
  shares, wd := setup(t)
  defer teardown(shares, wd)

  /* multiple shares */
  shares.add("s1", "foo/bar")
  shares.add("s2", "foo/bar2")
  if shares.query("s1/a") == nil { t.Error() }
  if shares.query("s2/a") == nil { t.Error() }
}

func Test_ChangingShares(t *testing.T) {
  shares, wd := setup(t)
  defer teardown(shares, wd)

  /* remove a file and make it disappear */
  shares.add("name", "foo")
  if shares.query("name/bar/a") == nil { t.Error() }
  err := os.Remove("foo/bar/a")
  if err != nil { t.Error(err) }
  shares.update()
  if shares.query("name/bar/a") != nil { t.Error() }

  /* add a file to the share */
  err = ioutil.WriteFile("foo/c", []byte("a"), os.FileMode(0644))
  if err != nil { t.Error(err) }
  shares.update()
  if shares.query("name/c") == nil { t.Error() }

  /* remove a directory */
  err = os.RemoveAll("foo/bar/baz")
  if err != nil { t.Error(err) }
  shares.update()
  if shares.query("name/bar/baz/a") != nil { t.Error() }
}
