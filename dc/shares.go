package dc

import "encoding/xml"
import "io"
import "os"
import "os/exec"
import "path/filepath"
import "regexp"
import "sync/atomic"
import "time"

import "github.com/alexcrichton/fargo/dc/tth"

type Shares struct {
  shares    chan Share
  delShares chan string
  queries   chan fileQuery
  hashers   chan *File
  cmds      chan command
  idle      chan int
  waiter    *fileQuery

  hashing   int32
  toHash    []*File
  tthMap    map[string]*File
}

type command int
const (
  stop command = iota
  rescan
)

type Share struct {
  dir     string
  name    string
}

type fileQuery struct {
  path      string
  response  chan *File
  wait      bool
}

var MaxWorkers = 4
var tthPattern = regexp.MustCompile("TTH/(\\w+)")

func NewShares() Shares {
  return Shares{shares:    make(chan Share),
                delShares: make(chan string),
                queries:   make(chan fileQuery),
                hashers:   make(chan *File),
                cmds:      make(chan command),
                idle:      make(chan int, 1),
                toHash:    make([]*File, 0),
                tthMap:    make(map[string]*File)}
}

func (s *Shares) save(c *Client, list *FileListing, xmlFile *File) {
  var err error
  defer func() {
    if err != nil {
      c.log("save error: " + err.Error())
    }
  }()

  /* Create the necessary directories and get a handle on the file */
  err = os.MkdirAll(c.CacheDir, os.FileMode(0755))
  if err != nil { return }
  file, err := os.Create(filepath.Join(c.CacheDir, "files.xml"))
  if err != nil { return }
  defer file.Close()

  /* Write out the contents to the file */
  _, err = file.WriteString(xml.Header)
  if err != nil { return }
  enc := xml.NewEncoder(file)
  err = enc.Encode(list)
  if err != nil { return }
  file.Close() /* flush contents, above defer will just return error */

  /* Unfortunately bzip2.Writer does not exist, so we're forced to shell out */
  cmd := exec.Command("bzip2", "-f", file.Name())
  err = cmd.Run()
  if err != nil { return }

  file, err = os.Open(file.Name() + ".bz2")
  if err != nil { return }
  info, err := file.Stat()
  if err != nil { return }
  xmlFile.Size = ByteSize(info.Size())
  xmlFile.realpath = file.Name()

  s.visit(&list.Directory)
}

func (s *Shares) visit(dir *Directory) {
  for _, f := range dir.Files {
    s.tthMap[f.TTH] = f
  }
  for i, _ := range dir.Dirs {
    s.visit(&dir.Dirs[i])
  }
}

func (s *Shares) hash(c *Client) {
  var err error
  list := FileListing{Version: "1.0.0", Generator: "fargo", Base: "/"}
  xmlList := File{Name: "files.xml.bz2"}

  for i := 0; i < MaxWorkers; i++ {
    go s.worker()
  }

  recheck := time.After(15 * time.Minute)
  s.save(c, &list, &xmlList)

  for {
    /* Send files to the hashers if we can */
    done := false
    for !done && len(s.toHash) > 0 {
      select {
        case s.hashers <- s.toHash[0]:  s.toHash = s.toHash[1:]
        default:                        done = true
      }
    }

    if s.waiter != nil && atomic.LoadInt32(&s.hashing) == 0 {
      /* Be sure we've updated tth hashes and saved the file list */
      s.save(c, &list, &xmlList)
      /* consume the idle signal if we can */
      select {
        case <-s.idle:
        default:
      }
      s.waiter.satisfy(s, &list, &xmlList)
      s.waiter = nil
    }

    /* wait for some activity via hashers or some command */
    select {
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
        recheck = time.After(15 * time.Minute)
        s.rescanShares(&list, c)

      case cmd := <-s.cmds:
        switch cmd {
          case stop:    return
          case rescan:  s.rescanShares(&list, c)
        }

      case <-s.idle:
        if atomic.LoadInt32(&s.hashing) != 0 { break }
        s.save(c, &list, &xmlList)

      case q := <-s.queries:
        if q.wait {
          s.waiter = &q
        } else {
          q.satisfy(s, &list, &xmlList)
        }
    }
  }
}

func (s *Shares) rescanShares(list *FileListing, c *Client) {
  var err error
  for i := 0; err == nil && i < len(list.Dirs); i++ {
    err = s.sync(c, list, Share{name: list.Dirs[i].Name,
                                  dir: list.Dirs[i].realpath})
  }
  if err != nil {
    c.log("rescan error: " + err.Error())
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
      file = &File{Name: name, realpath: f.Name()}
      d.Files = append(d.Files, file)
    }
    file.Size = ByteSize(info.Size())
    if info.ModTime().After(file.mtime) || file.TTH == "" {
      file.mtime = info.ModTime()
      file.TTH = ""
      atomic.AddInt32(&s.hashing, 1)
      s.toHash = append(s.toHash, file)
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
      delete(s.tthMap, dir.Files[i].TTH)
      dir.removeFile(i)
      i--
    }
  }

  return nil
}

func (s *Shares) query(path string) *File {
  response := make(chan *File)
  s.queries <- fileQuery{response: response, path: path, wait: false}
  return <-response
}

func (s *Shares) queryWait(path string) *File {
  response := make(chan *File)
  s.queries <- fileQuery{response: response, path: path, wait: true}
  return <-response
}

func (q *fileQuery) satisfy(s *Shares, list *FileListing, xmlList *File) {
  matches := tthPattern.FindStringSubmatch(q.path)
  if len(matches) == 2 && len(matches[1]) > 0 {
    q.response <- s.tthMap[matches[1]]
  } else if q.path == "files.xml.bz2" {
    q.response <- xmlList
  } else {
    f, _ := list.FindFile(q.path)
    q.response <- f
  }
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
  s.cmds <- rescan
}

func (s *Shares) halt() {
  s.cmds <- stop
  close(s.cmds)
  close(s.shares)
  close(s.queries)
  close(s.delShares)
  close(s.hashers)
}

func (s *Shares) worker() {
  for info := range s.hashers {
    file, err := os.Open(info.realpath)
    hash := ""
    if err == nil {
      hash, err = tth.Hash(file, uint64(info.Size))
    }
    if err == nil {
      info.TTH = hash
    } else {
      info.TTH = "fail"
    }
    atomic.AddInt32(&s.hashing, -1)
    /* Flag that a hasher is now idle, if we can't flag the someone else
     * already has and we can just go about our business as usual */
    select {
      case s.idle <- 1:
      default:
    }
  }
}
