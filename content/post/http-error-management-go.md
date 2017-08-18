---
title: HTTP and Error management in Go
tags:
  - Golang
  - HTTP
  - Error management
  - Middleware
categories:
  - Golang
draft: false
date: 2015-07-23 08:12:01
thumbnail: images/gopherswrench.jpg
toc: true
description: Create http handlers returning errors in Go.
---

Go comes with a great standard library including `net/http` which allow a developer to create a reliable http server very easily.

# TL;DR

Code and example can be found here: https://github.com/creack/ehttp

# Basic http server

To provide context, let's take a look at a basic http server in Go:

```go
package main

import (
        "fmt"
        "log"
        "net/http"
)

func handler(w http.ResponseWriter, req *http.Request) {
        fmt.Fprintln(w, "hello world")
}

func main() {
        http.HandleFunc("/", handler)
        log.Fatal(http.ListenAndServe(":8080", nil))
}
```

The first step is to define a handler. In order to be understood by the Go's http library, the handler needs to follow this specific prototype: `func(http.ResponseWriter, *http.Request)` which is defined as the `http.HandlerFunc` type.
Once we have our handler, we can register it on a specific route and then start the server.

This is great! In very few lines of code, we have a working web server ready to go!

# Error management

You might have noticed: our handler does not return an error... But luckily, the `net/http` package exposes the `http.Error` function in order to report an error to the client. This will set the Content-Type, send a custom http status header and write the error as the body.

Small example:

```go
func handler(w http.ResponseWriter, req *http.Request) {
        if err := doSomething(); err != nil {
                http.Error(w, err.Error(), http.StatusInternalServerError)
                return
        }
        fmt.Fprintln(w, "hello world")
}
```

As you can imagine, this can become cumbersome pretty fast. We could imagine writing a wrapper for `http.Error` which is going to log the error, send instrumentations and then call `http.Error`, but when doing a lot in a handler, we always need to have that call + return.
A nice way to go would be to consider the handler as a simple entrypoint and avoid doing any logic directly in the handler. This is a good approach, especially when you don't want to be tight to http and able to switch to other protocols.

# Custom Handler

A solution is to create a custom handler, let's try:

```go
type HandlerFunc func(http.ResponseWriter, *http.Request) error
```

Pretty straight forward for now, but wait, `http.HandleFunc` expects a different prototype, so we won't be able to use it anymore, right?
Kind of.. Right in a sense that we can't use it directly, but we always can work around anything ;)

## http.HandlerFunc

In order to "convert" our custom handler to the native http one, we need to write a middleware and we are going to use that to handle our error management.

So, what is a middleware? It a simple "layer" that comes in between the client's request and our final handler.

```go
// MWError is the main middleware. When an error is returned, it send
// the data to the client if the header hasn't been sent yet, otherwise, log them.
func MWError(hdlr HandlerFunc) http.HandlerFunc {
        return func(w http.ResponseWriter, req *http.Request) {
                if err := hdlr(w, req); err != nil {
						http.Error(w, err.Error(), http.StatusInternalError)
                        return
                }
        }
}
```

So, we have a function that takes our custom handler function as a parameter and return a native http HandlerFunc.

```go
router.HandleFunc("/", MWError(hdlr))
```

When the client calls our server, it ends up in that newly generated native http Handler which in turn calls our custom one and then handle the error.

## http.Handler

Alternatively, we can implement the `http.Handler` interface on our custom type so it can be used by all the `http` functions expecting that interface (I am thinking mainly about `http.Handle` and `http.ListenAndServe`

```go
type HandlerFunc func(http.ResponseWriter, *http.Request) error

func (hdlr HandlerFunc) ServeHTTP(w http.ResponseWriter, req *http.Request) {
        if err := hdlr(w, req); err != nil {
				http.Error(w, err.Error(), http.StatusInternalError)
                return
        }
}
```

# Going further

Now that we have a custom http handler and we can return error, we can think about improvements:
- smarter error management
- custom error type holding the HTTP Status
- panic recovery
- adaptors for non-standard library routers (gorilla, httprouter, etc)
- headers detection (we can't send error headers if they have already been sent)

I started a small library that implements all this: https://github.com/creack/ehttp, it is very very simple and close to the standard library.
