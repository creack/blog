---
title: Half a decade with Go - User side
tags:
  - Golang
  - alt.mylife
categories:
  - Golang
draft: false
toc: true
date: 2014-11-11 23:56:00
thumbnail: images/gophers5th.jpg
description: Small recap of go projects from the past 5 years.
---

Yesterday was Go 5th anniversary. For fun, I looked for trace of activity around that time. Today is the 5th anniversary of the oldest trace I found of myself playing with Go: 

http://go-lang.cat-v.org/irc-logs/old-go-nuts

> (11/11/2009) 23:56 -!- creack [n=creack@ip-67.net-80-236-112.lhaylesroses.rev.numericable.fr]
has joined #go-nuts

I will not repeat what has been said in the official Go blog, but here is a small history of what I have been playing with in Go.

## Timeline

- IRC bot (2009)
- Shell (2009/2010)
- FIX (4.4) Engine (2010)
- Trading platform (2010/2011)
- Crypto tools (2011)
- OpenCV (2011)
- "scripts" tools for platform / testing (2012)
- [Docker](https://github.com/docker/docker) (2013/2014)
- [Redis Server](https://github.com/creack/go-redis-server) (2013/2014)
- [Ray Tracer](https://github.com/creack/goray) (2014)
- Citrix Application Platform (2014)
- [Interactive Brokers API](https://github.com/gofinance/ib) (2014)

I'll try to talk about my experience through all this in future posts.

### IRC Bot

The first thing I did in order to try the language. It was fun and I ended up with a working bot pretty quickly. However, after couple of weeks, it was not compiling anymore and I never updated it.

An IRC bot is very easy to implement, you just need to play with network and strings. I think it is a nice exercice for anyone trying Go for the first time.

### Shell

As a student, one of my first project in C was a Shell, so I started to do the same in Go for learning purpose.
One of the issues was the signal management. Go didn't allow to catch `SIGQUIT` (`C-\`), so I had to call CGO for it. (Otherwise, when pressing `C-\`, even while running a process would kill the shell with a backtrace)
An other was the lack of `fork`. So I started to call the syscall with `SYS_FORK`. But then, I had issues with `wait()`: There is not `WAIT_ANY` macro. When using the common `-1`, I ended up with random behavior depending on the platform. Also, on darwin, `W_UNTRACED` didn't seem to be working.
Then comes the termcaps. A very important part of a shell is the UI, i.e. the command line. Setting things like the raw mode and the `ICANON` mode have been quite a challenge.


### FIX Engine

When I started to develop a trading platform, I needed to communicate with the broker using FIX4.4. I first looked at QuickFix, but it was C++ and I really wanted to use Go. So I started to rewrite an engine :)
Unfortunately, the language were still evolving very fast and I had to rewrite my code pretty often. Even though Go provided a tool to help the rewrite, it was often failing.
I also had issue with socket stability, I think related to some weird stuff done by the GC. In the end, I dropped Go and went back to C++.

### Trading Platform

Even though I dropped Go for the FIX Engine, I still used it for some other components. My favorite was a live vizualiser of Stock/Forex prices. You could subscrube to any Ticker and have a the prive live in a webpage.
I achieved this using Go and socket.io.
The backtest engine was also written in Go.

### Crypto Tools

In 2011, I played a lot with Cryptography. Even though it was already implemented in the standard library, I wrote an RSA and 3DES implementation.
I also wrote couple of tools to generate keys, try to "hack" an encrypted message, embed messages within image (steganography).

### OpenCV

In 2011, I found an OpenCV binding for Go, so I had fun with it. I implemented a Canny edge detection over the webcam, which I presented at the university. Thanks to this demo, I have been proposed a PhD at the [State university of St Petersburg, Russia](http://www.sut.ru) by [Dr., Professor Gennady Yanovsky](http://seti.sut.ru/?article=4005)

### Scripts for Platform / Testing

In 2012, while I was working in PHP for PrestaShop, I didn't get the chance to write much of Go. So each time I needed to write a script in order to test something, monitor a service, manage a server, instead of using Python or Bash, I always used Go :)

### Docker

In 2013, I started to work on Docker, once the 1.0 have been released, I took distance from the project.
There, I had similar issues as when I was working on a Shell: Termcaps, raw mode, fork, syscalls, etc.. However, Go was already in 1.0 and I managed to do everything I needed to.
The main big issue that we still can see the trace of today was the lack of pointer to method. This is why Docker REST Api uses functions instead of method: at the time, we could not pass methods around!

### Go Redis Server

While at Docker, I also worked on a Redis Server in Go. Something I really liked about this was the variable channel management. In Go, you can't use `select` on an arbitrary chan, you need to specify which one to use. In order to work around this, I had to "rebuild" `select` using the `relect` package.
The performances are not (yet) there, but the idea is.

### Ray Tracer

For quite some time, I wanted to write a Ray Tracer, so why not in Go? I found a X11 library in pure Go so I started.
I'll be talking about this more in depth at the [GopherCon](http://www.gophercon.in/) in Bangaluru, India in February, 2015.

### Citrix Application Platform

After Docker, I joined Citrix where I integrated the Application Platform Group. There I keep writing go on a daily basis. We migrate services from Ruby to Go and develop new ones.

### Interactive Brokers API

I have been using Interactive Brokers for quick some time now. I love them, however, there "interactive" is pretty difficult to use. In order to use their API, you need to run a local Java client (GUI, of course). They provide a Java and C++ sdk. The Gofinance project brings the power of Go to IB. And with Docker, I completely removed the need for the local GUI or even Java.

/mylife
