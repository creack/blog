---
title: Play with NSQ in Go
tags:
  - Golang
  - NSQ
  - Queue
categories:
  - Golang
  - NSQ
draft: false
date: 2014-10-19 17:42:42
toc: false
thumbnail: images/nsq.png
description: Dig a bit more into NSQ with Go.
---

In my previous article, we saw what was NSQ, now, let's try to play with it a bit more.

# Consumer

As we saw previously, we can directly publish on NSQD via http using curl, so let's focus for now on the consumer part.

NSQ provides a sample app that does the bridge between http and consumer: https://github.com/bitly/nsq/blob/master/apps/nsq_pubsub/nsq_pubsub.go

As the goal is to use it in an application, we don't need that HTTP overhead. Here is what is looks like stripped down: [playground](http://play.golang.org/p/q3uE91fGU-)

```go
package main

import (
        "fmt"

        nsq "github.com/bitly/go-nsq"
)

func nsqSubscribe(tcpAddr, topicName, channelName string, hdlr nsq.HandlerFunc) error {
        fmt.Printf("Subscribe on %s/%s\n", topicName, channelName)

        // Create the configuration object and set the maxInFlight
        cfg := nsq.NewConfig()
        cfg.MaxInFlight = 8

        // Create the consumer with the given topic and chanel names
        r, err := nsq.NewConsumer(topicName, channelName, cfg)
        if err != nil {
                return err
        }

        // Set the handler
        r.AddHandler(hdlr)

        // Connect to the NSQ daemon
        if err := r.ConnectToNSQD(tcpAddr); err != nil {
                return err
        }

        // Wait for the consumer to stop.
        <-r.StopChan
        return nil
}

func main() {
        nsqSubscribe("localhost:4150", "mytopic", "mychan1", func(msg *nsq.Message) error {
                fmt.Printf("%s\n", msg.Body)
                return nil
        })
}
```

It is very similar to the HTTP package, in a sense that you define your handler and give it to the NSQ consumer. You can try this example by starting `nsqd` locally, run this code and publish messages via curl:

```bash
curl -d 'hello world' 'localhost:4151/pub?topic=mytopic'
```

# Producer

Now let's see the Producer. It is nice for testing to be able to use `curl`, however in an actual application, the HTTP overhead can be a burden.
The Go implementation is even simpler than the consumer: [playground](http://play.golang.org/p/zl2BDJgnQb)

```go
package main

import nsq "github.com/bitly/go-nsq"

func nsqPublish(tcpAddr, topicName string, message []byte) error {
        // Create the configuration object and set the maxInFlight
        cfg := nsq.NewConfig()
        cfg.MaxInFlight = 8

        // Create the producer
        p, err := nsq.NewProducer(tcpAddr, cfg)
        if err != nil {
                return err
        }
        return p.Publish(topicName, message)
}

func main() {
        nsqPublish("localhost:4150", "mytopic", []byte(`hello world`))
}
```

You can now run the subscriber and N publisher to make sure it works. Note that `nsqd` need to be up and running and they both connect to it.

# Conclusion

**NSQ** is very easy to use and even more easy to integrate.  In a next article, we'll see how it performs with Benchmark.
