package dc

import "testing"
import "io/ioutil"
import "os"
import "path/filepath"

func Test_DownloadDestinations(t *testing.T) {
  dl := NewDownload("foo", "path/to/file")
  wd, err := filepath.EvalSymlinks(os.TempDir())
  if err != nil { t.Error(err) }
  wd, err = ioutil.TempDir(wd, "fargo")
  if err != nil { t.Error(err) }
  defer os.RemoveAll(wd)
  err = os.Chdir(wd)
  if err != nil { t.Error(err) }

  /* test relative-ness */
  dst, err := dl.destination("a")
  if err != nil { t.Error(err) }
  if dst != wd + "/a/path/to/file" { t.Error(dst, wd) }

  /* absolute from now on, don't let cwd muck with anything */
  err = os.Chdir("/")
  if err != nil { t.Error(err) }

  dst, err = dl.destination(wd + "/a")
  if err != nil { t.Error(err) }
  if dst != wd + "/a/path/to/file" { t.Error(dst) }

  dl.reldst = "to/file.ext"
  dst, err = dl.destination(wd + "/a")
  if err != nil { t.Error(err) }
  if dst != wd + "/a/to/file.ext" { t.Error(dst) }

  f, err := os.Create(wd + "/a/to/file.ext")
  if err != nil { t.Error(err) }
  f.Close()

  dst, err = dl.destination(wd + "/a")
  if err != nil { t.Error(err) }
  if dst != wd + "/a/to/file-1.ext" { t.Error(dst) }
}
