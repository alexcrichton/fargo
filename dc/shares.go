package dc

import "errors"
import "io"
import "os"
import "sync"
import "time"
import "path/filepath"
import "encoding/xml"

type Shares struct {
  roots  []string
  shares chan Share
  delShares chan string
  list   *FileListing
}

type Share struct {
  dir  string
  name string
}

type HashReq struct {
  path string
  tth  *string
}

type ShareHasher struct {
  hashers chan HashReq
  wg      sync.WaitGroup
}

var AlreadySharing = errors.New("already sharing the directory/file")
var NotSharing = errors.New("not sharing the directory/file")

var MaxWorkers = 4

func NewShares() Shares {
  return Shares{roots: make([]string, 0),
                shares: make(chan Share, 100),
                delShares: make(chan string, 0)}
}

func (s *Shares) hash(c *Client) {
  hasher := ShareHasher{hashers: make(chan HashReq)}
  list := FileListing{Version: "1.0.0", Generator: "fargo", Base: "/"}

  for i := 0; i < MaxWorkers; i++ {
    go hasher.worker(hasher.hashers)
  }

  recheck := time.After(5 * time.Second)

  for {
    c.log("Current file list: ")
    b, err := xml.MarshalIndent(list, "", "  ")
    if err == nil {
      c.log(string(b))
    } else {
      c.log("err: " + err.Error())
    }

    select {
      case share := <-s.shares:
        if list.Directory.childFile(share.name) != nil ||
           list.Directory.childDir(share.name) != nil {
          c.log("hash error: already sharing directory")
          break
        }
        err := hasher.sync(c, &list, share)
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
        recheck = time.After(5 * time.Second)
        for i := 0; i < len(list.Dirs); i++ {
          err := hasher.sync(c, &list, Share{name: list.Dirs[i].Name,
                                             dir: list.Dirs[i].realpath})
          if err != nil {
            c.log("hash error (" + list.Dirs[i].Name + "): " + err.Error())
          }
        }
    }
  }
}

func (h *ShareHasher) sync (c *Client, list *FileListing, sh Share) error {
  file, err := os.Open(sh.dir)
  if err != nil { return err }
  stat, err := file.Stat()
  if err != nil { return err }
  list.Directory.version++
  err = h.file(file, stat, &list.Directory, sh.name)
  file.Close()
  if err != nil { return err }
  /* wait for all the hashers to finish */
  h.wg.Wait()
  return nil
}

func (h *ShareHasher) file(f *os.File, info os.FileInfo, d *Directory,
                           name string) error {
  /* If we reached a file, then send a request for the hashers to hash */
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
      h.wg.Add(1)
      h.hashers <- HashReq{path: f.Name(), tth: &file.TTH}
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
      h.file(f2, info, dir, info.Name())
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

func (s *Shares) add(name, dir string) error {
  s.shares <- Share{dir: dir, name: name}
  return nil
}

func (s *Shares) remove(name string) error {
  s.delShares <- name
  return nil
}

func (h *ShareHasher) worker(reqs chan HashReq) {
  for req := range reqs {
    *req.tth = tth(req.path)
    println("hasing: ", req.path)
    h.wg.Done()
  }
}

/* TODO: implement this */
func tth(path string) string {
  return path
}
