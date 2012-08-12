package tth

import "testing"
import "os"
import "io"
import "io/ioutil"

func hash(t *testing.T, data string) string {
  file, err := ioutil.TempFile(os.TempDir(), "fargo")
  if err != nil { t.Fatal(err) }
  defer file.Close()
  defer os.Remove(file.Name())

  _, err = io.WriteString(file, data)
  if err != nil { t.Fatal(err) }
  _, err = file.Seek(0, os.SEEK_SET)
  if err != nil { t.Fatal(err) }

  tth, err := Hash(file, uint64(len(data)))
  if err != nil { t.Fatal(err) }
  return tth
}

func Test_TTH(t *testing.T) {
  h := hash(t, "foo\n")
  if h != "A2MPPCGS5CPJV6AOAP37ICDCFV3WYU7PBREC6FY" { t.Error(h) }
  h = hash(t, "")
  if h != "LWPNACQDBZRYXW3VHJVCJ64QBZNGHOHHHZWCLNQ" { t.Error(h) }
}
