package ui

/**
 * The CLI is separated into two goroutines. Because readline is not
 * thread-safe, all console I/O interactions happen from one goroutine. The
 * second goroutine notifies the first when input is available via select() on
 * stdin. If it were possible to wait on goroutines and file descriptors, then
 * this wouldn't be necessary.
 *
 * The main goroutine then lists to the message and io channels, printing all
 * mesages and dealing with io by notifying readline via
 * rl_callback_read_char(). This is the same thread which also handles
 * completions and things like that.
 *
 * The CLI is meant to be run on its own goroutine separate from the program,
 * and communication happens via the ui.Input interface.
 *
 * Due to what seems to be a bug in editline, OSX needs to have its own readline
 * installed (via homebrew currently) and link against that. I don't know much
 * about the bug, but apparently if you use rl_callback_handler_* functions then
 * a Ctrl+D after the first line of input refuses to do anything, and there's
 * some other odd bugs as well.
 *
 * Then again, this if my first go project and I could just be really bad at
 * figuring out what channels are as well.
 */

// #cgo darwin LDFLAGS: -lreadline.6 -L/usr/local/Cellar/readline/6.2.2/lib
// #cgo darwin CFLAGS: -I/usr/local/Cellar/readline/6.2.2/include
// #cgo linux LDFLAGS: -lreadline
//
// #include <stdlib.h>
// #include <stdio.h>
// #include <readline/readline.h>
// #include <readline/history.h>
//
// extern void fargo_install_rl(void);
// extern void fargo_wait_stdin(void);
// extern int fargo_select_stdin(void);
// extern void fargo_clear_rl(void);
// extern char*(*fargo_completion_entry)(char*, int);
import "C"

import "fmt"
import "os"
import "os/signal"
import "path"
import "sort"
import "strings"
import "strconv"
import "unsafe"

import "github.com/alexcrichton/fargo/dc"

type Terminal struct {
  msgs    chan string
  client  *dc.Client

  nick string
  cwd  string
  prompt *C.char
  promptChange bool
}

var activeTerm *Terminal

var completionResults []string

var commands = []string{"browse", "connect", "nicks", "ops", "help", "quit",
                        "ls", "pwd", "cd", "get", "share"}
var options = []string{"ulslots", "dlslots", "active", "passive", "hub",
                       "nick", "download"}

//export completeEach
func completeEach(c *C.char, idx int) *C.char {
  if completionResults != nil && idx < len(completionResults) {
    return C.CString(completionResults[idx])
  }
  return nil
}

func filter(arr []string, prefix string) []string {
  newarr := make([]string, 0)
  for _, s := range arr {
    if strings.HasPrefix(s, prefix) {
      newarr = append(newarr, s)
    }
  }
  return newarr
}

//export rawComplete
func rawComplete(ctext *C.char, a int, b int) **C.char {
  /* a, b are the limits of ctext in rl_line_buffer, so if a == 0 then we're
   * completing a command, otherwise the argument to a command */
  text := C.GoString(ctext)
  if a == 0 {
    completionResults = filter(commands, text)
  } else {
    line := C.GoString(C.rl_line_buffer)
    idx := strings.Index(line, " ")
    if idx > 0 {
      completionResults = activeTerm.complete(line[0:idx], line[idx+1:])
    } else {
      completionResults = nil
    }
  }

  /* if we're finishing a completion with one entry that's a directory, don't
   * append the ' ' character at the end to continue completion */
  if len(completionResults) == 1 {
    if strings.HasSuffix(completionResults[0], "/") {
      C.rl_completion_suppress_append = 1
    }
  }
  return C.rl_completion_matches(ctext, C.fargo_completion_entry)
}

//export receiveLine
func receiveLine(c *C.char) {
  if c == nil {
    activeTerm.quit()
  } else {
    activeTerm.Exec(C.GoString(c))
    C.add_history(c)
  }
}

func New(c *dc.Client) *Terminal {
  if activeTerm != nil {
    panic("Can't have two terminals!")
  }
  term := &Terminal{msgs: make(chan string, 10), client: c}
  activeTerm = term
  return term
}

func (t *Terminal) complete(cmd string, word string) []string {
  switch cmd {
  case "browse":
    nicks, err := activeTerm.client.Nicks()
    if err == nil {
      return filter(nicks, word)
    }

  case "set":
    if strings.Index(word, " ") == -1 {
      return filter(options, word)
    }

  case "cd", "ls", "get":
    if t.nick == "" {
      break
    }
    /* Complete only after the last "/" to complete only directories */
    idx := strings.LastIndex(word, "/")
    part1, part2 := "", word
    prep := ""
    if idx != -1 {
      part1, part2 = word[0:idx], word[idx+1:]
      prep = part1 + "/"
    }
    /* Find all files within the last finished directory */
    files, err := t.client.Listings(t.nick, t.resolve([]string{cmd, part1}))
    if files == nil || err != nil {
      break
    }
    idx = strings.LastIndex(word, " ")
    arr := make([]string, 0)
    /* if what was typed has a space in it, then only emit whatever's after
     * the space because that's the delimiter for readline completion */
    add := func(name string) {
      if idx == -1 {
        arr = append(arr, name)
      } else {
        t.msgs <- name[idx+1:]
        arr = append(arr, name[idx+1:])
      }
    }
    for _, dir := range files.Dirs {
      if strings.HasPrefix(dir.Name, part2) {
        add(prep + dir.Name + "/")
      }
    }
    if cmd == "get" {
      for _, file := range files.Files {
        if strings.HasPrefix(file.Name, part2) {
          add(prep + file.Name)
        }
      }
    }
    return arr
  }
  return nil
}

func (t *Terminal) err(e error) {
  println("error:", e.Error())
}

func (t *Terminal) resolve(parts []string) string {
  if len(parts) < 2 {
    return t.cwd
  }
  if path.IsAbs(parts[1]) {
    return path.Clean(parts[1])
  }
  return path.Clean(path.Join(t.cwd, parts[1]))
}

func (t *Terminal) Exec(line string) {
  line = strings.TrimSpace(line)
  idx := strings.Index(line, "#")
  if idx != -1 {
    line = line[0:idx]
  }
  if line == "" { return }
  parts := strings.SplitN(strings.TrimSpace(line), " ", 2)
  switch parts[0] {
  case "quit":
    activeTerm.quit()
  case "connect":
    err := t.client.ConnectHub(t.msgs)
    if err != nil {
      t.err(err)
    }
  case "nicks":
    nicks, err := t.client.Nicks()
    if err == nil {
      for _, n := range nicks {
        println(n)
      }
    } else {
      t.err(err)
    }
  case "ops":
    ops, err := t.client.Ops()
    if err == nil {
      for _, n := range ops {
        println(n)
      }
    } else {
      t.err(err)
    }
  case "browse":
    if len(parts) != 2 {
      println("usage: browse <nick>")
    } else {
      err := t.client.Browse(parts[1])
      if err == nil {
        t.nick = parts[1]
        t.cwd = "/"
        t.promptChange = true
      } else {
        t.err(err)
      }
    }

  case "get":
    if t.nick == "" {
      println("error: not browsing a nick")
    } else {
      err := t.client.Download(t.nick, t.resolve(parts))
      if err != nil { t.err(err) }
    }

  case "ls":
    if t.nick == "" {
      println("error: not browsing a nick")
    } else {
      path := t.resolve(parts)
      dir, err := t.client.Listings(t.nick, path)
      if err != nil {
        t.err(err)
        break
      }
      sort.Sort(dir)
      for _, d := range dir.Dirs {
        fmt.Printf("- %s/\n", d.Name)
      }
      for _, f := range dir.Files {
        fmt.Printf("%10s - %s\n", f.Size, f.Name)
      }
    }

  case "pwd":
    if t.nick == "" {
      println("error: not browsing a nick")
    } else {
      println(t.cwd)
    }
  case "cd":
    if t.nick == "" {
      println("error: not browsing a nick")
      break
    }
    newwd := t.resolve(parts)
    _, err := t.client.Listings(t.nick, newwd)
    if err != nil {
      t.err(err)
    } else {
      t.cwd = newwd
      t.promptChange = true
    }

  case "set":
    if len(parts) == 1 {
      println("usage: set <option> [<value>]")
      break
    }
    parts = strings.SplitN(parts[1], " ", 2)
    if len(parts) == 1 && parts[0] != "passive" {
      println("must specify an argument as well")
      break
    }

    switch parts[0] {
    case "hub":       t.client.HubAddress = parts[1]
    case "passive":   t.client.Passive = true
    case "nick":      t.client.Nick = parts[1]
    case "download":  t.client.DownloadRoot = parts[1]
    case "active":
      t.client.ClientAddress = parts[1]
      t.client.Passive = false

    case "ulslots", "dlslots":
      s, err := strconv.ParseInt(parts[1], 10, 32)
      if err != nil {
        t.err(err)
      } else if parts[0] == "dlslots" {
        t.client.DL.Cnt = int(s)
      } else {
        t.client.UL.Cnt = int(s)
      }
    }

  case "share":
    if len(parts) == 1 {
      println("usage: share <name> <directory>")
      break
    }
    parts := strings.SplitN(parts[1], " ", 2)
    if len(parts) == 1 {
      println("usage: share <name> <directory>")
      break
    }
    err := t.client.Share(parts[0], parts[1])
    if err != nil { t.err(err) }
  case "unshare":
    if len(parts) == 1 {
      println("usage: unshare <name>")
      break
    }
    err := t.client.Unshare(parts[1])
    if err != nil { t.err(err) }

  default:
    fmt.Println(`syntax: command [arg1 [arg2 ...]]
commands:
  help            this help
  quit            quit the client
  connect         connect to the hub
  nicks           show peers connected to the hub
  ops             show ops on the hub

browsing:
  browse <nick>   begin browsing a peer's files
  ls [dir]        when browsing a peer, list files in the current directory
  pwd             print the current directory
  cd [dir]        move into the specified directory, or with no argument go back
                  to the root directory

sharing:
  share <name> <directory>
  unshare <name>

configuration:
  set <option> [<value>]
      hub      address      Address of the hub to connect to
      nick     string       Local nick to assume
      passive               Don't have an active server, default
      active   address      Local address to bind to for an active server
      download string       Path at which to store downloads
      ulslots  integer      Number of upload slots to have
      dlslots  integer      Number of download slots to have
`)
  }
}

func (t *Terminal) Run() {
  C.fargo_install_rl()

  interrupts := make(chan os.Signal, 1)
  signal.Notify(interrupts, os.Interrupt)

  /* "event loop" for the terminal */
  err := 0
  for err >= 0 {
    if t.promptChange {
      t.promptChange = false
      if t.prompt != nil {
        C.free(unsafe.Pointer(t.prompt))
      }
      t.prompt = C.CString(t.nick + ":" + t.cwd + " $ ")
      C.rl_set_prompt(t.prompt)
      C.rl_redisplay()
    }
    /* Couldn't ever figure out FD_SET for select... */
    err = int(C.fargo_select_stdin())
    if err > 0 {
      C.rl_callback_read_char()
    }

    /* check for things to do from channels */
    looping := true
    for looping {
      select {
      case msg := <-t.msgs:
        C.fargo_clear_rl()
        println(msg)
        C.rl_forced_update_display()

      case <-interrupts:
        t.quit()

      default:
        looping = false
      }
    }
  }

  C.rl_callback_handler_remove()
}

func (t *Terminal) quit() {
  t.client.DisconnectHub()
  os.Stdin.Close()
}
