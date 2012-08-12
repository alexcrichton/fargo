package tth

// #cgo linux LDFLAGS: -lgcc_s
// #include <stdint.h>
// #include <stdlib.h>
// extern char *fargo_tth(int fd, uint64_t size);
import "C"

import "encoding/base32"
import "errors"
import "os"
import "unsafe"

func Hash(f *os.File, size uint64) (string, error) {
  ret := C.fargo_tth(C.int(f.Fd()), C.uint64_t(size))
  if ret == nil {
    return "", errors.New("error calculating TTH")
  }
  data := []byte(C.GoString(ret))
  C.free(unsafe.Pointer(ret))

  hash := base32.StdEncoding.EncodeToString(data)
  if hash[len(hash) - 1] == '=' {
    hash = hash[:len(hash) - 1]
  }
  return hash, nil
}
