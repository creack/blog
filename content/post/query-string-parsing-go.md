---
title: Parsing HTTP Query String in Go
tags:
  - Golang
  - HTTP
  - Parsing
categories:
  - Golang
draft: false
date: 2015-07-27 06:31:44
toc: true
thumbnail: images/gopher.png
description: Easily handle complex HTTP query string query string in Go.
---

# TL;DR

Code and examples can be found here: https://github.com/creack/httpreq

# HTTP Server

Go provides a very easy way to create a http server:

```go
package main

import (
        "fmt"
        "log"
        "net/http"
)

func handler(w http.ResponseWriter, req *http.Request) {
        fmt.Fprintf(w, "hello world\n")
}

func main() {
        log.Fatal(http.ListenAndServe(":8080", http.HandlerFunc(handler)))
}
// curl http://localhost:8080
```

But how to deal with data?

## JSON body

A common way to pass data is via a json encoded body:

```go
package main

import (
        "encoding/json"
        "fmt"
        "log"
        "net/http"
)

type query struct {
        Name string
}

func handler(w http.ResponseWriter, req *http.Request) {
        q := &query{}
        if err := json.NewDecoder(req.Body).Decode(q); err != nil {
                log.Printf("Error decoding body: %s", err)
                return
        }
        fmt.Fprintf(w, "hello %s\n", q.Name)
}

func main() {
        log.Fatal(http.ListenAndServe(":8080", http.HandlerFunc(handler)))
}
// curl -d '{"Name": "Guillaume"}' http://localhost:8080/
```

## Query String

But what if we want to pass data via query string? Typically, pagination and extra data.

Go, once again, expose everything necessary:

```go
package main

import (
        "fmt"
        "log"
        "net/http"
        "strconv"
)

func handler(w http.ResponseWriter, req *http.Request) {
        if err := req.ParseForm(); err != nil {
                log.Printf("Error parsing form: %s", err)
                return
        }
        l := req.Form.Get("limit")
        limit, err := strconv.Atoi(l)
        if err != nil {
                log.Printf("Error parsing limit: %s", err)
                return
        }

        dr := req.Form.Get("dryrun")
        dryRun, _ := strconv.ParseBool(dr)
        fmt.Fprintf(w, "hello world. Limit: %d, Dryrun: %t\n", limit, dryRun)
}

func main() {
        log.Fatal(http.ListenAndServe(":8080", http.HandlerFunc(handler)))
}
// curl 'http://localhost:8080?limit=42&dryrun=true'
```

As we can see, it works as expected, however, if we add more and more fields to our query string, the type conversions quickly become cumbersome.

# A Better Query String management

We know how to convert any string to any type.
We know what data we are expecting.
We should be able to do something similar to json.Unmarshal.

## Conversion functions

Let's start with our previous example: we need an int and a bool. However, the `strconv` functions have different prototypes and return a value.

It would be interesting to write a small helper that will set a value instead of returning it. That way, we could instantiate our query object and pass the fields to be set. In order to do so, we need to use pointers.

```go
package main

import (
        "fmt"
        "log"
        "net/http"
        "strconv"
)

type query struct {
        Limit  int
        DryRun bool
}

func parseBool(s string, dest *bool) error {
        // assume error = false
        *dest, _ = strconv.ParseBool(s)
        return nil
}

func parseInt(s string, dest *int) error {
        n, err := strconv.Atoi(s)
        if err != nil {
                return err
        }
        *dest = n
        return nil
}

func handler(w http.ResponseWriter, req *http.Request) {
        if err := req.ParseForm(); err != nil {
                log.Printf("Error parsing form: %s", err)
                return
        }
        q := &query{}
        if err := parseBool(req.Form.Get("dryrun"), &q.DryRun); err != nil {
                log.Printf("Error parsing dryrun: %s", err)
                return
        }
        if err := parseInt(req.Form.Get("limit"), &q.Limit); err != nil {
                log.Printf("Error parsing limit: %s", err)
                return
        }
        fmt.Fprintf(w, "hello world. Limit: %d, Dryrun: %t\n", q.Limit, q.DryRun)
}

func main() {
        log.Fatal(http.ListenAndServe(":8080", http.HandlerFunc(handler)))
}
```

## Make it generic

It is a bit better, but still could be improved. What if we'd like to have this in a generic way?

As we can see, the conversion helpers have a very similar prototype, let's make it the same using `interface{}`

```go
package main

import (
        "fmt"
        "log"
        "net/http"
        "strconv"
)

type query struct {
        Limit  int
        DryRun bool
}

func parseBool(s string, dest interface{}) error {
        d, ok := dest.(*bool)
        if !ok {
                return fmt.Errorf("wrong type for parseBool: %T", dest)
        }
        // assume error = false
        *d, _ = strconv.ParseBool(s)
        return nil
}

func parseInt(s string, dest interface{}) error {
        d, ok := dest.(*int)
        if !ok {
                return fmt.Errorf("wrong type for parseInt: %T", dest)
        }
        n, err := strconv.Atoi(s)
        if err != nil {
                return err
        }
        *d = n
        return nil
}

func handler(w http.ResponseWriter, req *http.Request) {
        if err := req.ParseForm(); err != nil {
                log.Printf("Error parsing form: %s", err)
                return
        }
        q := &query{}
        if err := parseBool(req.Form.Get("dryrun"), &q.DryRun); err != nil {
                log.Printf("Error parsing dryrun: %s", err)
                return
        }
        if err := parseInt(req.Form.Get("limit"), &q.Limit); err != nil {
                log.Printf("Error parsing limit: %s", err)
                return
        }
        fmt.Fprintf(w, "hello world. Limit: %d, Dryrun: %t\n", q.Limit, q.DryRun)
}

func main() {
        log.Fatal(http.ListenAndServe(":8080", http.HandlerFunc(handler)))
}
```

## Parsing object

Now that we have generic helpers, we can easily write a small object that will simplify the way we use it:

We need to store N parsing functions, so we'll need a slice (or a map). In order to parse a field, we need the helper function, but we also need the original string and the destination.

We have our object!

```go
type parsingMap []parsingMapElem

type parsingMapElem struct {
        Field string
        Fct   func(string, interface{}) error
        Dest  interface{}
}
```

Once our `paringMap` constructed, we then need to execute it, let's write the loop logic:

```go
func (p parsingMap) parse(form url.Values) error {
        for _, elem := range p {
                if err := elem.Fct(elem.Field, elem.Dest); err != nil {
                        return err
                }
        }
        return nil
}
```

We know can put everything together:

```go
package main

import (
        "fmt"
        "log"
        "net/http"
        "net/url"
        "strconv"
)

// conversion helpers
func parseBool(s string, dest interface{}) error {
        d, ok := dest.(*bool)
        if !ok {
                return fmt.Errorf("wrong type for parseBool: %T", dest)
        }
        // assume error = false
        *d, _ = strconv.ParseBool(s)
        return nil
}

func parseInt(s string, dest interface{}) error {
        d, ok := dest.(*int)
        if !ok {
                return fmt.Errorf("wrong type for parseInt: %T", dest)
        }
        n, err := strconv.Atoi(s)
        if err != nil {
                return err
        }
        *d = n
        return nil
}

// parsingMap
type parsingMap []parsingMapElem

type parsingMapElem struct {
        Field string
        Fct   func(string, interface{}) error
        Dest  interface{}
}

func (p parsingMap) parse(form url.Values) error {
        for _, elem := range p {
                if err := elem.Fct(elem.Field, elem.Dest); err != nil {
                        return err
                }
        }
        return nil
}

// http server
type query struct {
        Limit  int
        DryRun bool
}

func handler(w http.ResponseWriter, req *http.Request) {
        if err := req.ParseForm(); err != nil {
                log.Printf("Error parsing form: %s", err)
                return
        }
        q := &query{}
        if err := (parsingMap{
                {"limit", parseInt, &q.Limit},
                {"dryrun", parseBool, &q.DryRun},
        }).parse(req.Form); err != nil {
                log.Printf("Error parsing query string: %s", err)
                return
        }

        fmt.Fprintf(w, "hello world. Limit: %d, Dryrun: %t\n", q.Limit, q.DryRun)
}

func main() {
        log.Fatal(http.ListenAndServe(":8080", http.HandlerFunc(handler)))
}
```

# Going Further

I wrote this small library: https://github.com/creack/httpreq which provides more helpers and a cleaner API. It fits my current use case, but feel free to add any helper that can be missing :)
