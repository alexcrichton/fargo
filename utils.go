package fargo

import "bytes"
import "strings"

func write(buf *bytes.Buffer, b byte) {
  b = (b << 4) | (b >> 4)
  switch b {
  case 0:
    buf.WriteString("/%DCN000%/")
  case 5:
    buf.WriteString("/%DCN005%/")
  case 36:
    buf.WriteString("/%DCN036%/")
  case 96:
    buf.WriteString("/%DCN096%/")
  case 124:
    buf.WriteString("/%DCN124%/")
  case 126:
    buf.WriteString("/%DCN126%/")
  default:
    buf.WriteByte(b)
  }
}

func GenerateKey(lock []byte) []byte {
  newbytes := bytes.NewBuffer(nil)
  l := len(lock)

  write(newbytes, lock[0]^lock[l-1]^lock[l-2]^5)
  for i := 1; i < l; i++ {
    write(newbytes, lock[i]^lock[i-1])
  }
  return newbytes.Bytes()
}

func GenerateLock() (string, string) {
  return "EXTENDEDPROTOCOL" + strings.Repeat("ABC", 6),
    strings.Repeat("ABCD", 4)
}
