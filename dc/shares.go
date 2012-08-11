package dc

import "encoding/xml"
import "io"
import "os"
import "os/exec"
import "path/filepath"
import "time"

type Shares struct {
  roots     []string
  shares    chan Share
  delShares chan string
  queries   chan fileQuery
  hashers   chan HashReq
  stop      chan int
  rescan    chan int
  list      *FileListing
}

type Share struct {
  dir     string
  name    string
}

type fileQuery struct {
  path      string
  response  chan *File
}

type HashReq struct {
  path    string
  tth     *string
}

var MaxWorkers = 4

func NewShares() Shares {
  return Shares{roots:    make([]string, 0),
                shares:   make(chan Share),
                delShares:      make(chan string),
                queries:  make(chan fileQuery),
                hashers:  make(chan HashReq),
                stop:     make(chan int),
                rescan:   make(chan int)}
}

func (s *Shares) save(c *Client, list *FileListing) error {
  /* Create the necessary directories and get a handle on the file */
  err := os.MkdirAll(c.CacheDir, os.FileMode(0755))
  if err != nil { return err }
  file, err := os.Create(filepath.Join(c.CacheDir, "files.xml"))
  if err != nil { return err }
  defer file.Close()

  /* Write out the contents to the file */
  _, err = file.WriteString(xml.Header)
  if err != nil { return err }
  enc := xml.NewEncoder(file)
  err = enc.Encode(list)
  if err != nil { return err }
  file.Close() /* flush contents, above defer will just return error */

  /* Unfortunately bzip2.Writer does not exist, so we're forced to shell out */
  cmd := exec.Command("bzip2", "-f", file.Name())
  return cmd.Run()
}

func (s *Shares) hash(c *Client) {
  list := FileListing{Version: "1.0.0", Generator: "fargo", Base: "/"}

  for i := 0; i < MaxWorkers; i++ {
    go s.worker()
  }

  recheck := time.After(15 * time.Minute)

  for {
    err := s.save(c, &list)
    if err != nil {
      c.log("save error: " + err.Error())
    }

    select {
      case <-s.stop:
        return

      case share := <-s.shares:
        if list.Directory.childFile(share.name) != nil ||
           list.Directory.childDir(share.name) != nil {
          c.log("hash error: already sharing directory")
          break
        }
        share.dir, err = filepath.Abs(share.dir)
        if err == nil {
          err = s.sync(c, &list, share)
        }
        if err != nil {
          c.log("hash error: " + err.Error())
        }

      case share := <-s.delShares:
        for i := 0; i < len(list.Dirs); i++ {
          if list.Dirs[i].Name == share {
            list.removeDir(i)
            break
          }
        }

      case <-recheck:
      case <-s.rescan:
        recheck = time.After(15 * time.Minute)
        for i := 0; i < len(list.Dirs); i++ {
          err := s.sync(c, &list, Share{name: list.Dirs[i].Name,
                                        dir: list.Dirs[i].realpath})
          if err != nil {
            c.log("hash error (" + list.Dirs[i].Name + "): " + err.Error())
          }
        }

      case q := <-s.queries:
        f, _ := list.FindFile(q.path)
        q.response <- f
    }
  }
}

func (s *Shares) sync(c *Client, list *FileListing, sh Share) error {
  file, err := os.Open(sh.dir)
  if err != nil { return err }
  stat, err := file.Stat()
  if err != nil { return err }
  list.Directory.version++
  err = s.file(file, stat, &list.Directory, sh.name)
  file.Close()
  if err != nil { return err }

  return nil
}

func (s *Shares) file(f *os.File, info os.FileInfo, d *Directory,
                      name string) error {

  if !info.IsDir() {
    d.removeDirName(name)
    file := d.childFile(name)
    if file == nil {
      d.Files = append(d.Files, File{Name: name, realpath: f.Name()})
      file = &d.Files[len(d.Files) - 1]
    }
    file.Size = ByteSize(info.Size())
    if info.ModTime().After(file.mtime) {
      file.mtime = info.ModTime()
      file.TTH = ""
      s.hashers <- HashReq{path: f.Name(), tth: &file.TTH}
    }
    file.version = d.version
    return nil
  }

  /* For a directory, descend into each file/directory */
  d.removeFileName(name)
  dir := d.childDir(name)
  if dir == nil {
    d.Dirs = append(d.Dirs, NewDirectory(name, f.Name()))
    dir = &d.Dirs[len(d.Dirs) - 1]
  }
  dir.version = d.version

  /* Ensure all current files update to the current version and are hashed */
  for {
    infos, err := f.Readdir(100)
    if err == io.EOF {
      break
    } else if err != nil {
      return err
    }

    for _, info := range infos {
      f2, err := os.Open(filepath.Join(f.Name(), info.Name()))
      if err != nil { return err }
      s.file(f2, info, dir, info.Name())
      f2.Close()
    }
  }

  /* Prune out old files and directories */
  for i := 0; i < len(dir.Dirs); i++ {
    if dir.Dirs[i].version != dir.version {
      dir.removeDir(i)
      i--
    }
  }
  for i := 0; i < len(dir.Files); i++ {
    if dir.Files[i].version != dir.version {
      dir.removeFile(i)
      i--
    }
  }

  return nil
}

func (s *Shares) query(path string) *File {
  response := make(chan *File)
  s.queries <- fileQuery{response: response, path: path}
  return <-response
}

func (s *Shares) add(name, dir string) error {
  s.shares <- Share{dir: dir, name: name}
  return nil
}

func (s *Shares) remove(name string) error {
  s.delShares <- name
  return nil
}

func (s *Shares) update() {
  s.rescan <- 1
}

func (s *Shares) halt() {
  s.stop <- 1
  close(s.shares)
  close(s.queries)
  close(s.delShares)
  close(s.hashers)
}

func (s *Shares) worker() {
  for req := range s.hashers {
    *req.tth = tth(req.path)
  }
}

/* TODO: implement this */
func tth(path string) string {
  time.Sleep(1)
  return path
}
