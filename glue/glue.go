package glue

import "fmt"

type Control interface {
  Browse(string) error
  Nicks() ([]string, error)
  Ops() ([]string, error)
  ConnectHub(chan string) error
  DisconnectHub() error
  Listings(string, string) (Directory, error)
  DownloadFile(string, string) error
}

type Directory interface {
  Name() string
  DirectoryCount() int
  Directory(int) Directory
  FileCount() int
  File(int) File
}

type File interface {
  Name() string
  Size() ByteSize
  TTH() string
}

type ByteSize float64

const (
  _           = iota // ignore first value by assigning to blank identifier
  KB ByteSize = 1 << (10 * iota)
  MB
  GB
  TB
)

func (b ByteSize) String() string {
  switch {
  case b >= TB:
    return fmt.Sprintf("%.2fTB", b/TB)
  case b >= GB:
    return fmt.Sprintf("%.2fGB", b/GB)
  case b >= MB:
    return fmt.Sprintf("%.2fMB", b/MB)
  case b >= KB:
    return fmt.Sprintf("%.2fKB", b/KB)
  }
  return fmt.Sprintf("%.2fB", b)
}
