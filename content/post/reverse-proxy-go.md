---
title: Reverse Proxy in Go
tags:
  - Golang
  - Reverse Proxy
  - Load Balancing
categories:
  - Golang
draft: false
date: 2015-07-10 12:02:21
toc: true
thumbnail: images/gc15-logo.svg
description: Simple multi-host reverse proxy using the Go stdlib.
---

# TL;DR

The final code can be found here: https://github.com/creack/goproxy

# Goal

In this article, we are going to dive into the standard library's *Reverse Proxy* and see how to use it as a load balancer with persistent connections that doesn't lose any requests!

Here is our example setup:

- Service One - version 1 running on `http://localhost:9091/` and `http://localhost:9092/`
- Reverse Proxy on `http://localhost:9090/< service name>/< service version>/`

When calling `http://localhost:9090/serviceone/v1/`, we want the proxy to balance between
`http://localhost:9091/` and `http://localhost:9092/` without loosing any request if one of the hosts goes down.

# Standard Library Example

Let's start with the doc: http://godoc.org/net/http/httputil#ReverseProxy.
We can see that the `ReverseProxy` structure has the `ServerHTTP` method, which means that we can use it as HTTP router directly with `http.ListenAndServe`.
There is also `NewSingleHostReverseProxy`, which sound great: we have an example on how to instantiate a `ReverseProxy` that works with a single host! So let's see what it looks like:

```go
// NewSingleHostReverseProxy returns a new ReverseProxy that rewrites
// URLs to the scheme, host, and base path provided in target. If the
// target's path is "/base" and the incoming request was for "/dir",
// the target request will be for /base/dir.
func NewSingleHostReverseProxy(target *url.URL) *ReverseProxy {
        targetQuery := target.RawQuery
        director := func(req *http.Request) {
                req.URL.Scheme = target.Scheme
                req.URL.Host = target.Host
                req.URL.Path = singleJoiningSlash(target.Path, req.URL.Path)
                if targetQuery == "" || req.URL.RawQuery == "" {
                        req.URL.RawQuery = targetQuery + req.URL.RawQuery
                } else {
                        req.URL.RawQuery = targetQuery + "&" + req.URL.RawQuery
                }
        }
        return &ReverseProxy{Director: director}
}
```

The function takes a target as a parameter. This is going to be our target host URL.
Let's skip the `RawQuery` part, it is simply used to forward properly the query string arguments.
Then we have `director` which we then give to the `ReverseProxy` object. This is what defines the behavior of our *reverse proxy*.
That *director* function takes the destination query as a parameter and needs to update it with the expected parameter. First, we need to set the request's URL, the important parts are the `Scheme` and `Host`. The `Path` and `RawQuery` are used to manipulate the HTTP route.

So let's try!

First, let's write a small http server which is going to be our target server:

```go
package main

import (
        "log"
        "net/http"
        "os"
        "strconv"
)

func main() {
        if len(os.Args) != 2 {
                log.Fatalf("Usage: %s <port>", os.Args[0])
        }
        if _, err := strconv.Atoi(os.Args[1]); err != nil {
                log.Fatalf("Invalid port: %s (%s)\n", os.Args[1], err)
        }

        http.HandleFunc("/", func(w http.ResponseWriter, req *http.Request) {
                println("--->", os.Args[1], req.URL.String())
        })
        http.ListenAndServe(":"+os.Args[1], nil)
}
```

This small http server listens on the first command line argument port and when called, displays the port and the http request url.

Now, let's write a small *reverse proxy*:

```go
package main

import (
        "net/http"
        "net/http/httputil"
        "net/url"
)

func main() {
        proxy := httputil.NewSingleHostReverseProxy(&url.URL{
                Scheme: "http",
                Host:   "localhost:9091",
        })
        http.ListenAndServe(":9090", proxy)
}
```

The code is straight forward: We create a new single host *reverse proxy* that targets `http://localhost:9091/` and listens on **9090**.

Try it! It works fine. `curl http://localhost:9090` forwards properly to our http server running on **9091**.

# Multiple hosts case

The example we saw is working great and is very simple, but not really useful in production. What if we want to have more than one host?

## Director

As we saw earlier, the main logic of the *reverse proxy* resides in the `Director` member. So let's try to create our own `ReverseProxy` object.
We are going to copy/paste the `httputil.NewSingleHostReverseProxy` code and change the prototype to take a slice of url so we can balance between given hosts and alter the code to use a random host from the given ones.

```go
package main

import (
        "log"
        "math/rand"
        "net/http"
        "net/http/httputil"
        "net/url"
)

// NewMultipleHostReverseProxy creates a reverse proxy that will randomly
// select a host from the passed `targets`
func NewMultipleHostReverseProxy(targets []*url.URL) *httputil.ReverseProxy {
        director := func(req *http.Request) {
                target := targets[rand.Int()%len(targets)]
                req.URL.Scheme = target.Scheme
                req.URL.Host = target.Host
                req.URL.Path = target.Path
        }
        return &httputil.ReverseProxy{Director: director}
}

func main() {
        proxy := NewMultipleHostReverseProxy([]*url.URL{
                {
                        Scheme: "http",
                        Host:   "localhost:9091",
                },
                {
                        Scheme: "http",
                        Host:   "localhost:9092",
                },
        })
        log.Fatal(http.ListenAndServe(":9090", proxy))
}
```

## Demo time

< script type="text/javascript" src="https://asciinema.org/a/23263.js" id="asciicast-23263" async></script>

## Caveat

At the end of the previous demo, I kill one of the http server and we can see that the reverse proxy yield errors when hitting that host. This result in request loss, which is not ideal. Having a host going down happens, it should be the role of our proxy to make sure the client's request reaches the expected target.

In order to understand what is going on, let's dive in the `ServerHTTP` method. We can see at the beginning:

```go
        transport := p.Transport
        if transport == nil {
                transport = http.DefaultTransport
        }
```

This means that because we didn't provide a `Transport` object, the *reverse proxy* will use the default one.
Now let's take a look at the default `Transport`:

```go
var DefaultTransport RoundTripper = &Transport{
        Proxy: ProxyFromEnvironment,
        Dial: (&net.Dialer{
                Timeout:   30 * time.Second,
                KeepAlive: 30 * time.Second,
        }).Dial,
        TLSHandshakeTimeout: 10 * time.Second,
}
```

`Proxy` is a function that will apply the proxy settings, by default, it looks up the env `HTTP_PROXY` and co.
The next one is more interesting: `Dial`. It defines how to establish the connection to the target host. The default `Transport` uses the `Dialer` from `net` with some timeouts/keepalive settings.

The error yielded by the *reverse proxy* when one host went down is: `http: proxy error: dial tcp 127.0.0.1:9091: getsockopt: connection refused `. It is pretty clear: the issue comes from `Dial`.

To understand the behavior, let's extend a bit our code to add some output so we can see exactly what gets called and when.

```go
package main

import (
        "log"
        "math/rand"
        "net"
        "net/http"
        "net/http/httputil"
        "net/url"
        "time"
)

// NewMultipleHostReverseProxy creates a reverse proxy that will randomly
// select a host from the passed `targets`
func NewMultipleHostReverseProxy(targets []*url.URL) *httputil.ReverseProxy {
        director := func(req *http.Request) {
		        println("CALLING DIRECTOR")
                target := targets[rand.Int()%len(targets)]
                req.URL.Scheme = target.Scheme
                req.URL.Host = target.Host
                req.URL.Path = target.Path
        }
        return &httputil.ReverseProxy{
                Director: director,
                Transport: &http.Transport{
                        Proxy: func(req *http.Request) (*url.URL, error) {
		                        println("CALLING PROXY")
		                        return http.ProxyFromEnvironment(req)
	                    },
                        Dial: func(network, addr string) (net.Conn, error) {
                                println("CALLING DIAL")
                                conn, err := (&net.Dialer{
                                        Timeout:   30 * time.Second,
                                        KeepAlive: 30 * time.Second,
                                }).Dial(network, addr)
                                if err != nil {
                                        println("Error during DIAL:", err.Error())
                                }
                                return conn, err
                        },
                        TLSHandshakeTimeout: 10 * time.Second,
                },
        }
}

func main() {
        proxy := NewMultipleHostReverseProxy([]*url.URL{
                {
                        Scheme: "http",
                        Host:   "localhost:9091",
                },
                {
                        Scheme: "http",
                        Host:   "localhost:9092",
                },
        })
        log.Fatal(http.ListenAndServe(":9090", proxy))
}
```

What did we do? We simply reused the code of `http.DefaultTransport` and add some logging.

## More Verbose Demo

< script type="text/javascript" src="https://asciinema.org/a/23265.js" id="asciicast-23265" async></script>

As we can see, `Dial` is called only the first time `Director` yields a host, after that it reuses the already existing connection in the internal's pool of `ReverseProxy`
When one of the servers goes away, the `ReverseProxy` receives `EOF` and remove the connection from the pool resulting in a new call to `Dial` upon next request.

# Routing

Let's put the request loss on the side for the moment and address the routing based on the request's path.

## Service Registry

In order to easily lookup an endpoint for a given service, let's create a small `Registry` type instead of using a slice of `*url.URL`:

```go
type Registry map[string][]string

var ServiceRegistry = Registry{
    "serviceone/v1": {
	    "localhost:9091",
	    "localhost:9092",
    },
}
```

## Extract Service and Version from Request

In order to know what service we are targeting, we use the `/serviceName/serviceVersion/` prefix in the path.

```go
func extractNameVersion(target *url.URL) (name, version string, err error) {
        path := target.Path
        // Trim the leading `/`
        if len(path) > 1 && path[0] == '/' {
                path = path[1:]
        }
        // Explode on `/` and make sure we have at least
        // 2 elements (service name and version)
        tmp := strings.Split(path, "/")
        if len(tmp) < 2 {
                return "", "", fmt.Errorf("Invalid path")
        }
        name, version = tmp[0], tmp[1]
        // Rewrite the request's path without the prefix.
        target.Path = "/" + strings.Join(tmp[2:], "/")
        return name, version, nil
}
```

It is pretty straightforwrd but wait, where does that `target *url.URL` comes from?
You might have guess, it is the `req.URL` from our `Director`.

## Registry Example

Let's put all this together based on our first multi host example:

```go
package main

import (
        "log"
        "math/rand"
        "net"
        "net/http"
        "net/http/httputil"
        "net/url"
        "time"
)

type Registry map[string][]string

func extractNameVersion(target *url.URL) (name, version string, err error) {
        path := target.Path
        // Trim the leading `/`
        if len(path) > 1 && path[0] == '/' {
                path = path[1:]
        }
        // Explode on `/` and make sure we have at least
        // 2 elements (service name and version)
        tmp := strings.Split(path, "/")
        if len(tmp) < 2 {
                return "", "", fmt.Errorf("Invalid path")
        }
        name, version = tmp[0], tmp[1]
        // Rewrite the request's path without the prefix.
        target.Path = "/" + strings.Join(tmp[2:], "/")
        return name, version, nil
}

// NewMultipleHostReverseProxy creates a reverse proxy that will randomly
// select a host from the passed `targets`
func NewMultipleHostReverseProxy(reg Registry) *httputil.ReverseProxy {
        director := func(req *http.Request) {
		        name, version, err := extractNameVersion(req.URL)
		        if err != nil {
			        log.Print(err)
			        return
		        }
                endpoints := reg[name+"/"+version]
                if len(endpoints) == 0 {
                        log.Printf("Service/Version not found")
                        return
                }
                req.URL.Scheme = "http"
                req.URL.Host = endpoints[rand.Int()%len(endpoints)]
        }
        return &httputil.ReverseProxy{
                Director: director,
        }
}

func main() {
        proxy := NewMultipleHostReverseProxy(Registry{
                        "serviceone/v1": {"localhost:9091"},
                        "serviceone/v2": {"localhost:9092"},
        })
        log.Fatal(http.ListenAndServe(":9090", proxy))
}
```

We now have a working load balancer!
But we still have an issue when a host goes down..

# Avoid loosing request

So, what can we do? When a host is down, the error comes from `Dial` but our logic is in `Director`.
So let's move the logic to `Dial`! Indeed, it would be great but there is one big issue:
`Dial` does not know anything about the request: we can't lookup the target service endpoint list.
In order to work around this, we are going to do something a bit hackish: use the `Request`'s `Host` has a placeholder!
We are going to put `serviceName/serviceVersion` has a string inside the `Request` which later on will be passed on to `Dial` where we can lookup the endpoints for our services.

```go
func NewMultipleHostReverseProxy(reg Registry) *httputil.ReverseProxy {
	director := func(req *http.Request) {
		name, version, err := extractNameVersion(req.URL)
		if err != nil {
			log.Print(err)
			return
		}
		req.URL.Scheme = "http"
		req.URL.Host = name + "/" + version
	}
	return &httputil.ReverseProxy{
		Director: director,
		Transport: &http.Transport{
			Proxy: http.ProxyFromEnvironment,
			Dial: func(network, addr string) (net.Conn, error) {
				// Trim the `:80` added by Scheme http.
				addr = strings.Split(addr, ":")[0]
				endpoints := reg[addr]
				if len(endpoints) == 0 {
					return nil, fmt.Errorf("Service/Version not found")
				}
				return net.Dial(network, endpoints[rand.Int()%len(endpoints)])
			},
			TLSHandshakeTimeout: 10 * time.Second,
		},
	}
}
```

# Going further

## Registry

The `github.com/creack/goproxy/registry` package exposes a `Registry` interface:

```go
// Registry is an interface used to lookup the target host
// for a given service name / version pair.
type Registry interface {
        Add(name, version, endpoint string)                // Add an endpoint to our registry
        Delete(name, version, endpoint string)             // Remove an endpoint to our registry
        Failure(name, version, endpoint string, err error) // Mark an endpoint as failed.
        Lookup(name, version string) ([]string, error)     // Return the endpoint list for the given service name/version
}
```

`Add` and `Delete` are used to control the content of our registry. We might want to call `Add` when a new host is available and `Delete` when one goes away.
`Failure` is called when `Dial` fails, which probably means the target is not available anymore. We can use that method to store how many time it fails and eventually call `Delete` to remove the faulty host.
It is a good place to put some logging and instrumentation.
`Lookup` is pretty straight forward, it returns the hosts list for the given service name/version.

This interface can be implemented using *ZooKeeper*, *etcd*, *consul* or any service you might be using. The default implementation is a naive map.

## Load Balancer

The `github.com/creack/goproxy` package is basically our latest example hooked with the `Registry` interface.

In top of `NewMultiplHostReverProxy`, it also exposes two functions: `ExtractNameVersion` and `LoadBalance`. They are not exposed in order to be used, but in order to be overridden.

`ExtractNameVersion` can be replace by a custom one in order to have a different path model.
`LoadBalance` is the load balancer logic. It takes the target service name and version as well as the registry and yield a `net.Conn`. The default one is a random but can be replaced by a smarter one.
