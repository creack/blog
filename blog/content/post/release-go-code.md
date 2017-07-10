---
title: "Release Go code (and others) via Docker using Makefile"
tags:
  - Golang
  - Docker
  - Release process
date: 2014-11-09T19:01:11-05:00
---

<center>
<img border="0" src="http://ddf912383141a8d7bbe4-e053e711fc85de3290f121ef0f0e3a1f.r87.cf1.rackcdn.com/docker-whale.png" />
</center>

In this article, I'll demonstrate how to leverage Makefile in order to release lightweight Docker image for production.

## Sample Application code

```golang
package main

func main() {
        println("hello world")
}
```

Of course, do not forget to vendor your dependencies: `godep save`.

In order to create a release image, we first need to build the binary. We will have 2 Dockerfiles.

## Main Dockerfile

The main Dockerfile is the "classic" one. For our example:

```plain
# Using google/golang as base image
FROM            google/golang:stable
# Install Godep for vendoring
RUN             go get github.com/tools/godep
# Recompile the standard library without CGO
RUN				CGO_ENABLED=0 go install -a std
# Declare the maintainer
MAINTAINER      Guillaume J. Charmes <guillaume@charmes.net>

# For convenience, set an env variable with the path of the code
ENV             APP_DIR         $GOPATH/src/example

# Set the entrypoint as the binary, so `docker run <image>` will behave as the binary
ENTRYPOINT      ["/example"]
# Add the sources to the APP_DIR
ADD             .       $APP_DIR
# Compile the binary and statically link
RUN             cd $APP_DIR && CGO_ENABLED=0 godep go build -o /example -ldflags '-d -w -s'
```

Note that the `godep`  install and the CGO disabled std rebuild are done before the maintainer, this allows to keep the cache for this part when the maintainer changes.
In a future article, I'll talk more in depth about static linking in Go (the `-ldflags` and `go install std` thingy)

## Release Dockerfile

In order to release, we need a second Dockerfile. As Docker builds directories, we need to create a subdirectory `release`.

The release Makefile is very straight forward and look like this:

```plain
# Use "scratch" as base: it is an empty image.
FROM            scratch
# Set the entrypoint as the binary, so `docker run <image>` will behave as the binary
ENTRYPOINT      ["/example"]
# Add the binary. As it is statically linked, no need to add libc or anything else.
ADD             example /
```

Now, we need a Makefile to automate the process

## Makefile

The Makefile allow for easy dependency scripting.

The goal is to push a "release" image. In order to do this, we need to have that image built. 
In order to build this image, we need the binary, In order to get the binary, we need to build.
In order to build, we need the source. For convenience, we monitor `.` instead of each individual go files.

The default rule is `all` which triggers `build`

`build` depends on `.build` which is a file. If it exists then move on to the next dependency, otherwise, execute the rule. `.build` depend on `.`. This means that if anything changes in the current directoty, the cache gets invalidated and the rule will be executed.
In order to build, we call `docker build` and create the `.build` file.
The result is a full blown image roughly 600MB. `release` will help with this.
The first step is to extract the binary and `/etc/ssl`. The `/etc/ssl` is mandatory only if you plan on using SSL (otherwise, Go will complain it does not find the certificates). Once extracted in a tarball, we build the release Dockerfile.

```plain
NAME            = example
DOCKER_IMAGE    = 127.0.0.1:5000/$(NAME)

all             : build

.build          : .
                docker build -t $(NAME) .
                docker inspect -f '{{.Id}}' $(NAME) > .build

build           : .build

release/$(NAME) : build
                docker run --rm --entrypoint /bin/sh $(NAME) -c 'tar cf - /$(NAME) /etc/ssl' > $@ || (rm -f $@; false)
                docker build --rm -t $(DOCKER_IMAGE) release

release         : release/$(NAME)

push            : release
                docker push $(DOCKER_IMAGE)

clean           :
                $(RM) .build release/$(NAME)

.PHONY          : push release build all clean
```

## Directory tree

In the end, the directory tree should look like this:

```plain
$> tree
.
├── Dockerfile
├── Godeps
│   ├── Godeps.json
│   ├── Readme
│   └── _workspace
├── Makefile
├── main.go
└── release
    └── Dockerfile

3 directories, 6 files
```


## Conclusion

As we saw, the release process is a dependency cascade, which make the Makefile very useful.
The advantages of using something like this is easily shown by `docker images`:

Original image
```plain
$> docker images example
REPOSITORY          TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
example             latest              e68fcc5482a8        10 seconds ago          605.3 MB
```

Release image
```plain
$> docker images 127.0.0.1:5000/example
REPOSITORY               TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
127.0.0.1:5000/example   latest              6e9e455bf60d        4 seconds ago          617.6 kB
```
