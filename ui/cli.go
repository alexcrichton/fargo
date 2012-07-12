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
// #import <stdlib.h>
// #import <stdio.h>
// #import <readline/readline.h>
//
// extern void fargo_install_rl(void);
// extern void fargo_wait_stdin(void);
// extern int fargo_select_stdin();
import "C"

import "fmt"
import "log"
import "os"
import "os/signal"

type Input interface {
  ReceiveCommand() Command
  Log(string)
}

type Terminal struct {
  cmds chan Command
  msgs chan string
}

type Command int
type action int

const (
  Connect = 0
  Quit Command = 1

  inputAvailable = 0
  uninstall action = 1
)

var activeTerm *Terminal

//export complete
func complete(c *C.char, a int, b int) **C.char {
  fmt.Printf("complete: %d %d\n", a, b)
  return nil
}

func parse(line string) (Command, bool) {
  switch line {
    case "q", "quit": return Quit, false
    case "c", "connect": return Connect, false
  }
  return Connect, true
}

//export receiveLine
func receiveLine(c *C.char) {
  var cmd Command
  var err bool
  if c == nil {
    cmd, err = Quit, false
  } else {
    cmd, err = parse(C.GoString(c))
  }
  if err {
    println("bad cmd")
  } else {
    activeTerm.cmds <- cmd
  }
}

func NewTerminal() *Terminal {
  if activeTerm != nil {
    log.Fatal("Can't have two terminals!")
  }
  term := &Terminal{make(chan Command), make(chan string)}
  activeTerm = term
  return term
}

func (t *Terminal) Start() {
  C.fargo_install_rl()

  interrupts := make(chan os.Signal, 1)
  signal.Notify(interrupts, os.Interrupt)

  /* "event loop" for the terminal */
  err := 0
  for err >= 0 {
    /* Couldn't ever figure out FD_SET for select... */
    err := C.fargo_select_stdin()
    if err > 0 {
      C.rl_callback_read_char()
    }

    /* check for things to do from channels */
    select {
      case msg := <-t.msgs:
        println(msg)

      case <-interrupts:
        t.cmds <- Quit

      default: /* just fall through if nothing to receive */
    }
  }

  C.rl_callback_handler_remove()
}

func (t *Terminal) Stop() {
  os.Stdin.Close()
}

func (t *Terminal) ReceiveCommand() Command {
  return <- t.cmds
}

func (t *Terminal) Log(msg string) {
  t.msgs <- msg
}
