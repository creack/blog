---
title: Privileged Listen in Go
tags:
  - Golang
  - Unix
  - Privilege
  - Listen
  - HTTP
categories:
  - Golang
draft: false
date: 2015-06-20 17:42:42
toc: true
description: Cleanly de-escalate after initiating privileged listen in Go.
---

# Introduction

Go does not play well with Forks and User permission. The reason is because it is a threaded runtime and there is no mechanism for clean fork or clean setuid.

To work around the fork issue, Go exposes `syscall.ForkExec()` which perform the fork (locked) but always perform an `Exec()` in the forked process, resulting in the calling one to disappear (overridden).

# The Issue.

https://github.com/golang/go/issues/1435

```bash
$> GOMAXPROCS=4 ./test 65534 65534
```

and note output:

```bash
goroutine 1: uid=0 euid=0 gid=0 egid=0
goroutine 2: uid=0 euid=0 gid=0 egid=0
goroutine 3: uid=0 euid=0 gid=0 egid=0
goroutine 4: uid=0 euid=0 gid=0 egid=0
goroutine 5: uid=0 euid=0 gid=0 egid=0
goroutine 6: uid=0 euid=0 gid=0 egid=0
goroutine 7: uid=0 euid=0 gid=0 egid=0
goroutine 8: uid=0 euid=0 gid=0 egid=0
goroutine 9: uid=0 euid=0 gid=0 egid=0
goroutine 0: uid=65534 euid=65534 gid=65534 egid=65534
goroutine 1: uid=0 euid=0 gid=0 egid=0
goroutine 2: uid=0 euid=0 gid=0 egid=0
goroutine 3: uid=0 euid=0 gid=0 egid=0
goroutine 4: uid=0 euid=0 gid=0 egid=0
goroutine 5: uid=0 euid=0 gid=0 egid=0
goroutine 6: uid=0 euid=0 gid=0 egid=0
goroutine 7: uid=0 euid=0 gid=0 egid=0
goroutine 8: uid=0 euid=0 gid=0 egid=0
goroutine 9: uid=0 euid=0 gid=0 egid=0
goroutine 0: uid=65534 euid=65534 gid=65534 egid=65534
```

It would be annoying if our http Handler was ran as root!

# The solution

To solve this issue, I wrote a small util: https://github.com/creack/golisten.

The idea is simple: perform the listen as root and then override the whole process with yourself as non-root.

```go
package main

import (
    "fmt"
    "log"
    "net/http"
    "os/user"

    "github.com/creack/golisten"
)

func handler(w http.ResponseWriter, req *http.Request) {
    u, err := user.Current()
    if err != nil {
        log.Printf("Error getting user: %s", err)
        return
    }
    fmt.Fprintf(w, "%s\n", u.Uid)
}

func main() {
    http.HandleFunc("/", handler)
    log.Fatal(golisten.ListenAndServe("guillaume", ":80", nil))
}
```

# Note

`golisten` is intended to be used with the `http` lib, but the concept can be used for any privilege de-escalation.
It is safe because we override the whole process, so all our active thread are from the child process.

# Caveat

As we re-exec ourself, we need to be careful with what is done prior the call the `golisten`.
Maybe a bit more cumbersome, but it is best to use `golisten.Listen` at the beginning and pass around the listener to `http.Serve()` later on.

```go
package main

import (
        "fmt"
        "log"
        "net/http"
        "os/user"

        "github.com/creack/golisten"
)

func handler(w http.ResponseWriter, req *http.Request) {
        u, err := user.Current()
        if err != nil {
                log.Printf("Error getting user: %s", err)
                return
        }
        fmt.Fprintf(w, "%s\n", u.Uid)
}

func main() {
        ln, err := golisten.Listen("guillaume", "tcp", ":80")
        if err != nil {
                log.Fatal(err)
        }
        http.HandleFunc("/", handler)
        println("ready")
        log.Fatal(http.Serve(ln, nil))
}
```
