---
title: Benchmarking NSQ
tags:
  - Golang
  - NSQ
  - Queue
  - Testing
  - Benchmark
categories:
  - Golang
  - NSQ
draft: false
date: 2014-10-26 17:42:42
toc: false
thumbnail: images/nsq.png
description: Use NSQ to write Go benchmarks and evaluate performances.
---

In this article, I'll demonstrate:

1. How to properly write tests that needs external services
2. How to write a parallel benchmark
3. NSQ performances

# Properly test services

## Self contained

The idea is to write self-contained tests that do not leak one into an other. It is particularly useful when testing databases, http server or in our case, **nsqd**.

For http tests, we use `httptest.NewServer()` which can be closed in a defer. That way, you have a brand new server each time. For databases, the best would be to mock, but if you can't, then create a new connection object, empty or create a new database, then defer destruction or empty.

In our case, for **nsqd**, we will simply spawn a new daemon, disable all logging, disable the dump of the queue on disc and destroy that daemon when the test is finished.

We could have done something much more simple and spawn an **nsqd** first then run our tests against that instance, but then the tests would not be consistent as what has been done by one test can affect the result of an other test.

## Other note

A pattern which I like is to create helpers in test that instead of returning an error, take the testing object.

Go provides the `testing.TB` interface which allow to receive either `*testing.B` or `*testing.T`. This is nice when writing helper for both tests and benchmarks.

Instead of having:

```go
func newObject(addr string) (*object, error) {
    if false {
        return nil, err
    }
    return &object{}, nil
}

func TestObject(t *testing.T) {
    obj, err := newObject("localhost")
    if err != nil {
        t.Fatal(err)
    }
    _ = obj
}
```

You would have:

```go
func newObject(t testing.TB, addr string) *object {
    if false {
        t.Fatal(err)
    }
    return &object{}
}

func TestObject(t *testing.T) {
    obj := newObject(t, "localhost")
    _ = obj
}
```


# Parallel Benchmark

It is very easy in Go to write parallel benchmarks:

From the [Go documentation](http://golang.org/pkg/testing/#example_B_RunParallel):

```go
package main

import (
	"bytes"
	"testing"
	"text/template"
)

func BenchmarkTemplate(b *testing.B) {
	// Parallel benchmark for text/template.Template.Execute on a single object.
	templ := template.Must(template.New("test").Parse("Hello, {{.}}!"))
	// RunParallel will create GOMAXPROCS goroutines
	// and distribute work among them.
	b.RunParallel(func(pb *testing.PB) {
		// Each goroutine has its own bytes.Buffer.
		var buf bytes.Buffer
		for pb.Next() {
			// The loop body is executed b.N times total across all goroutines.
			buf.Reset()
			templ.Execute(&buf, "World")
		}
	})
}
```

So, instead of the "regular" benchmark where you do something like

```go
func BenchmarkSomething(b *testing.B) {
    for i := 0; i < b.N; i++ {
        doSomething()
    }
}
```

you simply do:

```go
func BenchmarkSomething(b *testing.B) {
	b.RunParallel(func(pb *testing.PB) {
	    for pb.Next() {
	        doSomething()
	    }
	}
}
```

You will note that we do note use `b.N` anymore.

Good to know as well: `b.SetParallel(int)` will specify the amount of goroutines allowed.

# NSQ performances

## Write benchmark for nsqd

Nothing is better than an example: [Playground](http://play.golang.org/p/XpWwaKwE_n)

```go
package main

import (
	"io/ioutil"
	"log"
	"os"
	"runtime"
	"testing"
)

import (
	nsq "github.com/bitly/go-nsq"
	"github.com/bitly/nsq/nsqd"
)

// nopLogger simply discard any logs it receives
type nopLogger struct{}

func (*nopLogger) Output(int, string) error {
	return nil
}

// newDaemon creates a quiet, stripped down daemon and start it
func newDaemon() *nsqd.NSQD {
	opts := nsqd.NewNSQDOptions()

	// Disable http/https
	opts.HTTPAddress = ""
	opts.HTTPSAddress = ""
	// Disable logging
	opts.Logger = &nopLogger{}
	// Do not create on disc queue
	opts.DataPath = "/dev/null"

	nsqd := nsqd.NewNSQD(opts)
	nsqd.Main()
	return nsqd
}

// Wrap nsq.Consumer so we have control over Stop behavior
type consumer struct{ *nsq.Consumer }

func (c *consumer) Stop() {
	c.Consumer.Stop()
	<-c.Consumer.StopChan
}

// newConsumer creates a quiet connected Consumer
func newConsumer(t testing.TB, tcpAddr, topicName, channelName string, hdlr nsq.HandlerFunc) *consumer {
	// Create the configuration object and set the maxInFlight
	cfg := nsq.NewConfig()
	cfg.MaxInFlight = 8

	// Create the consumer with the given topic and chanel names
	r, err := nsq.NewConsumer(topicName, channelName, cfg)
	if err != nil {
		t.Fatal(err)
	}

	// Disable logging
	r.SetLogger(&nopLogger{}, 0)

	// Set the handler
	r.AddHandler(hdlr)

	// Connect to the NSQ daemon
	if err := r.ConnectToNSQD(tcpAddr); err != nil {
		t.Fatal(err)
	}

	return &consumer{Consumer: r}
}

// newProducer creates a quiet connected Producer
func newProducer(t testing.TB, tcpAddr string) *nsq.Producer {
	// Create the configuration object and set the maxInFlight
	cfg := nsq.NewConfig()
	cfg.MaxInFlight = 8

	// Create the producer
	p, err := nsq.NewProducer(tcpAddr, cfg)
	if err != nil {
		t.Fatal(err)
	}

	// Disable logging
	p.SetLogger(&nopLogger{}, 0)

	return p
}

func BenchmarkPubSub(b *testing.B) {
	// Disable general logging.
	log.SetOutput(ioutil.Discard)
	defer func() { log.SetOutput(os.Stderr) }()

	// Start NSQD and make sure to shut it down when leaving.
	nsqd := newDaemon()
	defer nsqd.Exit()

	// Create the consumer and send every message to the chan.
	msgs := make(chan []byte)
	hdlr := func(msg *nsq.Message) error { msgs <- msg.Body; return nil }
	consumer := newConsumer(b, "localhost:4150", "mytopic", "mychan1", hdlr)
	defer consumer.Stop()

	// Create producer.
	producer := newProducer(b, "localhost:4150")
	defer producer.Stop()

	// Tell Go to use as many cores as available.
	b.SetParallelism(runtime.NumCPU())

	// reset Go's timer.
	b.ResetTimer()

	// Run in Parallel
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			// Send "hello world" to NSQ and wait for it to arrive.
			if err := producer.Publish("mytopic", []byte("hello world")); err != nil {
				b.Fatal(err)
			}
			if msg, ok := <-msgs; !ok {
				b.Fatal("Message chan closed.")
			} else if expect, got := "hello world", string(msg); expect != got {
				b.Fatalf("Unexpected message. Expected: %s, Got: %s", expect, got)
			}
		}
	})
}
```

## Results

On my MacbookPro i7 8 cores 2Ghz:

```bash
$> GOMAXPROCS=8 go test -v -bench . .
PASS
BenchmarkPubSub-8    50000           37167 ns/op
ok      github.com/bitly/nsq/apps/test/bench    3.425s
```

So this is roughly 27K messages per seconds or 0.0004ms per send/receive operation.

Now let's see the impact of GOMAXPROCS:

```bash
$> for i in {1..8}; do GOMAXPROCS=$i go test -v -bench . .; done
BenchmarkPubSub             5         271720061 ns/op
BenchmarkPubSub-2          10         135813612 ns/op
BenchmarkPubSub-3          20          92693480 ns/op
BenchmarkPubSub-4          20          67964795 ns/op
BenchmarkPubSub-5          50          52089680 ns/op
BenchmarkPubSub-6          50          47146900 ns/op
BenchmarkPubSub-7          50          32083808 ns/op
BenchmarkPubSub-8       50000             37167 ns/op
```

# Conclusion

It is the first queueing service I am trying so I don't really know if it is good or bad, it would be interesting to compare with 0mq, redis, rabbitmq to see the difference.

In any case, it is a nice example for self-contained test leveraging the parallel capabilities of Go.
