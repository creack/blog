
---
title: Futures in Go
tags:
  - Golang
  - Futures
categories:
  - Golang
draft: false
date: 2014-11-22 05:53:10
toc: true
thumbnail: images/gopher.png
description: Use the futures/promises patterns in Go.
---

# The Problem

You have a function that returns an error, you want to run it in a goroutine. How to retrieve the error?

# The Solution

I'll take the example of Docker utils package: (from master on 08/06/2014)
https://github.com/docker/docker/blob/66c8f87e89ba0dd824cf640a159210fbbb8019ec/utils/utils.go#L40

```golang[<8;34;19m
func Go(f func() error) chan error {
        ch := make(chan error, 1)
        go func() {
                ch <- f()
        }()
        return ch
}
```


This small function effectively solves the issue: it starts the given function in a goroutine and return a chan which can be read to retrieve the error.

# An other problem

While this work in lot of cases, sometime, in top of retrieving the error, you might as well want to retrieve some data.
Docker's utils.Go() is nice and generic but it is maybe too generic for some situation.

Let's take the example of a crawler, I want to do N http request and display the content, but I want to do so concurrently and I still want all the responses and all the errors.

A way to achieve this would be to return a `chan struct { Reponse, error}` instead of `chan error`, but I don't really like that way. I prefer to return a future.

# Futures / Promises

Nothing works better than an example:

```golang
package main

import (
        "io/ioutil"
        "log"
        "net/http"
        "regexp"
)

// CrawlFuture represent the actual future.
// When called, it "promises" that the request has been done
// and returns the values as if it were synchronous.
type CrawlFuture func() (*http.Response, error)

// Crawl initiates the http request and return the future
func Crawl(url string) CrawlFuture {
        var (
                ch  = make(chan *http.Response)
                err error
        )

        go func(url string) {
                defer close(ch)

                req, e1 := http.Get(url)
                err = e1
                ch <- req
        }(url)

        return func() (*http.Response, error) {
                return <-ch, err
        }
}

var regexTitle = regexp.MustCompile("<title>(.*?)</title>")

func getTitle(resp *http.Response) string {
        body, err := ioutil.ReadAll(resp.Body)
        resp.Body.Close()
        if err != nil {
                return "error with response"
        }
        matches := regexTitle.FindSubmatch(body)
        if len(matches) < 2 {
                return "no title found"
        }
        return string(matches[1])
}

func main() {
        urls := []string{
                "http://google.com",
                "http://yandex.com",
                "http://www.baidu.com",
                "http://invalid",
        }
        futures := make([]CrawlFuture, 0, len(urls))
        for _, url := range urls {
                futures = append(futures, Crawl(url))
        }
        for _, future := range futures {
                resp, err := future()
                if err != nil {
                        log.Printf("Error: %s\n", err)
                        continue
                }
                if resp.StatusCode != 200 {
                        log.Printf("Invalid status: %s %d\n", resp.Status, resp.StatusCode)
                        continue
                }
                println(getTitle(resp))
        }
}
```

Instead of returning a chan, I create the chan internally and return a function that wait on the chan. It allows to start N request at the same time while being able to call the future later like if it were synchronous.

# Bonus

We could pass a `sync.WaitGroup` to the `Crawl` function. That way, we can initiate the crawl, do processing on the side and have a channel signal when all requests are done so we can go check the result.

```golang
ackage main

import (
        "io/ioutil"
        "log"
        "net/http"
        "regexp"
        "sync"
        "time"
)

// CrawlFuture represent the actual future.
// When called, it "promises" that the request has been done
// and returns the values as if it were synchronous.
type CrawlFuture func() (*http.Response, error)

// Crawl initiates the http request and return the future
func Crawl(url string, wg *sync.WaitGroup) CrawlFuture {
        var (
                ch  = make(chan *http.Response)
                err error
        )

        wg.Add(1)
        go func(url string) {
                defer close(ch)

                req, e1 := http.Get(url)
                err = e1
                wg.Done()
                ch <- req
        }(url)

        return func() (*http.Response, error) {
                return <-ch, err
        }
}

var regexTitle = regexp.MustCompile("<title>(.*?)</title>")

func getTitle(resp *http.Response) string {
        body, err := ioutil.ReadAll(resp.Body)
        resp.Body.Close()
        if err != nil {
                return "error with response"
        }
        matches := regexTitle.FindSubmatch(body)
        if len(matches) < 2 {
                return "no title found"
        }
        return string(matches[1])
}

func main() {
        urls := []string{
                "http://google.com",
                "http://yandex.com",
                "http://www.baidu.com",
                "http://invalid",
        }
        wg := &sync.WaitGroup{}
        done := make(chan struct{})

        futures := make([]CrawlFuture, 0, len(urls))
        for _, url := range urls {
                futures = append(futures, Crawl(url, wg))
        }
        go func() { wg.Wait(); close(done) }()

        select {
        case <-time.After(5 * time.Second):
                log.Fatal("timeout")
        case <-done:
                for _, future := range futures {
                        resp, err := future()
                        if err != nil {
                                log.Printf("Error: %s\n", err)
                                continue
                        }
                        if resp.StatusCode != 200 {
                                log.Printf("Invalid status: %s %d\n", resp.Status, resp.StatusCode)
                                continue
                        }
                        println(getTitle(resp))
                }
        }
}
```

That way, you have the warranty that your loop in the `done` case will be non-blocking. People familiar with `select(2)` will be happy: don't start something unless you know it is ready.
