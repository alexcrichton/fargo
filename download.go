package fargo

import "fmt"
import "os"
import "path/filepath"

type download struct {
  nick   string
  file   string
  tth    string
  offset uint64
  size   int64
  reldst string
}

const FileList = "files.xml.bz2"

func (c *Client) download(dl *download) error {
  if dl == nil { panic("can't download nil") }
  p := c.peer(dl.nick, func(p *peer) {
    if p.state != Uninitialized {
      return
    }
    if c.Passive {
      c.recvconnect(dl.nick)
    } else {
      c.connect(dl.nick)
    }
    p.state = RequestingConnection
  })

  p.Lock()
  p.push(dl)
  p.Unlock()
  return c.initiateDownload()
}

func (d *download) fileList() bool {
  return d.file == FileList
}

func (d *download) destination(root string) (string, error) {
  root, err := filepath.Abs(root)
  if err != nil {
    return "", err
  }
  path := filepath.Clean(filepath.Join(root, d.reldst))
  dir, file := filepath.Split(path)
  err = os.MkdirAll(dir, os.ModeDir | os.FileMode(0755))
  if err != nil {
    return "", err
  }

  /* file lists are special in that they are overwritten frequently */
  if d.fileList() {
    file = d.nick + "-" + file
    path := filepath.Join(dir, file)
    os.Remove(path) // ignore error
    return path, nil
  }

  tries, suffix := 0, ""
  ext := filepath.Ext(file)
  filebase := file[0:len(file)-len(ext)]
  for {
    path = filepath.Join(dir, filebase + suffix + ext)
    _, err := os.Stat(path)
    if err != nil {
      break
    }
    tries++
    if tries > 100 {
      panic("your file system is wack")
    }
    suffix = fmt.Sprintf("-%d", tries)
  }
  return path, nil
}

func NewDownload(nick string, file string) *download {
  return &download{nick: nick, file: file, size: -1, reldst: file}
}

func NewDownloadFile(nick string, path string, file *File) *download {
  return &download{nick: nick, file: path[1:], size: int64(file.Size),
                   tth: file.TTH, reldst: path}
}
