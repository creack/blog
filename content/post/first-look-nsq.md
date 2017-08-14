---
title: First look at NSQ
tags:
  - NSQ
  - Queue
categories:
  - NSQ
draft: false
date: 2014-10-12 17:42:42
toc: true
thumbnail: images/nsq.png
description: First look at NSQ and small demo.
---

I finally took the time to take a look at NSQ and it is pretty neat!

## What is NSQ?

From their website ([http://nsq.io/](http://nsq.io)):

> **NSQ** is a realtime distributed messaging platform designed to operate at scale, handling billions of messages per day.

Basically, it is a Queue the scales. It has been created by [bitly](https://bitly.com/) and they use it in production, so it has proven its performances. Since, a lot of other companies adopted it.34

It provides an HTTP api and easy way to create producer/consumers.

The code is available on github: https://github.com/bitly/nsq. They provide a set of helpers in the "apps" directory.

## Components

NSQ is composed of several compenent: nsq, nsqd, nsqlookupd, nsqadmin, but today, we'll talk only about `nsq` (client) and `nsqd` (queue daemon)

## Concept of the Queue

The idea of a Queue is to "queue" (who would have guessed? ;) messages. So we will have a `procuder` that sends messages to the queue, and in the other side, we will have a `consumer` that pops messages. A nice feature of most queuing systems is what we call `pub/sub`. I.e. multiple **consumers** can "subscribe" to the queue and a message **published** by a **producer** will be received by **1** or **N** **consumers**

## Topic and Channels

NSQ allows two mode of communication: `broadcast` and `balancing`.

- **broadcast**: A message published will be received by all subscribers
- **balancing**: A message published will be received by (at least) one subscriber.

In order to control this, NSQ provides two concepts: `topic` and `channel`.

When a consumer is created, it will subscribe to a **topic/channel** pair. However, when a producer is created, it will only publish to a **topic**.

A message published on a topic will be copied (broadcast) to each channels, then distributed within this channel.

Let's see an example:

### Balancing

- Consumer1 subscribe to `mytopic / mychannel`
- Consumer2 subscribe to `mytopic / mychannel`
- Consumer3 subscribe to `mytopic / mychannel`
- Producer1 published to `mytopic`

In this scenario, each message published will be received only by a single consumer. In a perfect world, if `Producer1` publishes 3 messages, each consumer will receive one. (In reality, it is random, but you get the idea).

### Broadcast

- Consumer1 subscribe to `mytopic / mychannel1`
- Consumer2 subscribe to `mytopic / mychannel2`
- Consumer3 subscribe to `mytopic / mychannel3`
- Producer1 published to `mytopic`

In this scenario, each message published will be received by all the consumers, because they all subscribed to a different channel. If `Producer1` publishes 3 messages, each consumer will receive all 3 messages.

### Broadcast + Balancing

Example from nsq.io:

- Consumer1 subscribe to `clicks / metrics`
- Consumer2 subscribe to `clicks / metrics`
- Consumer3 subscribe to `clicks / metrics`
- Consumer4 subscribe to `clicks / spam_analytics`
- Consumer5 subscribe to `clicks / archives`
- Producer1 published to `clicks`

In this scenario, if `Producer1` publishes 3 messages:

- Consumer1 receives 1 message (because balanced on the channel)
- Consumer2 receives 1 message
- Consumer3 receives 1 message
- Consumer4 receives 3 message (each message is copied to all the different channels)
- Consumer5 receives 3 message

Once you get the concept, the schema on their website makes a lot of sense:

{{% img src="images/nsq-design.gif" %}}

## Usage

Now let's try by ourselve!

### NSQD

NSQD is the queue "deamon" (not really a daemon as any go apps), it handles all the queuing logic and can be started with no particular configuration.
It is go gettable and can be installed with `go get github.com/bitly/nsq/apps/nsqd`
Now, simply start it:

```bash
$> nsqd
```

It will listen on port 4150 (tcp) and 4151 (http). We will see in a bit what those are for.

### Test application

NSQD provides an HTTP API, however, we can only **publish** on it. In order to **subscribe**, we need to use the tcp API. Thankfully, they provide an app that does just that an expose **subscribe** over http.

You can install this adaptor by doing `go get github.com/bitly/nsq/apps/nsq_pubsub`
Now, simply start it by providing the address of the daemon:

```bash
$> nsq_pubsub --nsqd-tcp-address localhost:4150
```

It will listen on 8080 (http)

### Demo time

Now that we have `nsqd` and `nsq_pubsub` up and running, we can simply try the queue with `curl`:

```bash
# Consumer on the adaptor
curl 'http://localhost:8080/sub?topic=mytopic&channel=mychan'
# Producer on nsqd
curl -d 'message' 'http://localhost:4151/pub?topic=mytopic
```

Let's open multiple terminal and reproduce the *bitly* example (`tmux` is your friend ;):
One consumer per terminal as it is blocking:

```bash
# Consumer1
curl 'http://localhost:8080/sub?topic=clicks&channel=metric'
# Consumer2
curl 'http://localhost:8080/sub?topic=clicks&channel=metric'
# Consumer3
curl 'http://localhost:8080/sub?topic=clicks&channel=metric'
# Consumer4
curl 'http://localhost:8080/sub?topic=clicks&channel=spam_analytics'
# Consumer5
curl 'http://localhost:8080/sub?topic=clicks&channel=archive'
# Producer
for i in {1..100}; do curl -d "message $i" 'http://localhost:4151/pub?topic=clicks'; done
```

## Conclusion

**NSQ** seems like a good alternative to legacy systems like RabbitMQ, in a next post, I'll try to do some benchmarks to assess performances and reliability.

I really like how easy it is to use and get started, the Broadcast/Distributed modes allow for nice and powerful scenarios.
