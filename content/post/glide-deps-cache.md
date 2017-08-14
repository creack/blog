---
title: Glide Cache and Docker
tags:
  - Golang
  - Glide
  - Godep
  - Docker
  - jq
categories:
  - Golang
  - Docker
draft: false
date: 2016-12-17 15:12:00
toc: false
thumbnail: images/glide-logo.png
description: Caching go dependencies build with Glide and Docker.
---

# Intro

Dependency management in **Golang** got a lot better since `go1.5`, however, we still need tools to manage it.

For a long time, I used [Godep](https://github.com/tools/godep) which was working great, but handles everything based on your local `GOPATH` which result in massive change sets in **git** each time a different team member updates them, which makes the code review difficult.

Here comes [Glide](http://glide.sh/). A "newcomer" which uses a **yaml** config in order to explicitly set the dependency version needed. It is based on **semver** and allow for automatic update of path/minor version, in a similar way as `npm`.

Once the initial config is set (and `glide` allows to automatically generate it), `glide up` will generate a `.lock` file with the expected commit, based on the **remote** version specified in the **yaml** config.

# Docker

For many reasons, Docker is a great tool and is a time saver. However, when it comes to develop in Go in a Docker environment, things quickly become slow, especially when using a lot of dependencies.

Let's take a naive `Dockerfile`:

```dockerfile
FROM       golang:1.7
ENV        APP_DIR $GOPATH/src/github.com/org/myapp
WORKDIR    $APP_DIR
ENTRYPOINT ["myapp"]
ADD        . $APP_DIR
RUN        go install
```

Each time something changes in the local directory, the `ADD` instruction will have its cache invalidated, resulting in the following `go install` to recompile the whole code, including all dependencies.

This is a major inconvenience when actively developing when we need to often recompile and/or run the tests, especially when dealing with statically linked, `CGO` disabled program.

## Godep

With **Godep**, in `go1.4`, a simple solution is to add the `Godeps` directory first, compile it and then add the rest of the app. 
In order to do that, we iterate over the dependency list and install them. As **Godep** uses **json**, we'll need [jq](https://stedolan.github.io/jq/), an awesome tool in order to play with **json** in the shell.

```dockerfile
FROM       golang:1.4
# Install jq and Godep.
RUN        apt-get update && apt-get install -y jq && go get github.com/tools/godep
ENV        APP_DIR $GOPATH/src/github.com/org/myapp
WORKDIR    $APP_DIR
ENTRYPOINT ["myapp"]
# Add Godeps and precompile.
ADD        Godeps/ $APP_DIR/Godeps
RUN        for pkg in $(cat Godeps/Godeps.json | jq -r '.Deps[].ImportPath'); do \
             godep go install $pkg; \
           done
# Add App and install.
ADD        . $APP_DIR
RUN        godep go install
```

This is nice and saves up quite a lot of time, however, since `go1.5`, the **vendor** model changed and the imported packages are now scoped within the package itself instead of using the `GOPATH` one, which make this method obsolete.

If you are curious about the magic line `for pkg in $(cat Godeps/Godeps.json | jq -r '.Deps[].ImportPath'); do godep go install -ldflags -d $pkg; done`, here is what it does:
**Godep** stores the known dependencies in the **json** file `Godeps/Godeps.json` which contains a **json object** with a `Deps` key which contains an **array** of dependencies. Each of which are a **json object** with the key `ImportPath` which is the value that interest us.
`cat Godeps/Godeps.json | jq -r '.Deps[].ImportPath'` returns a list of values from the **json** file, which we iterate on via the `for` loop and then install the dependency.

## Glide

With **glide**, in `go1.5` and up, we need to rethink a bit the process. It will be similar, however, the first issue is that **glide** uses a **yaml** config. How to extract the values from a shell command?

### yaml2json

I looked for tools similar to **jq** for **yaml** but didn't find much so I built  [yaml2json](https://github.com/creack/yaml2json) which is a small **go** util which simply translate **yaml** to **json** using `github.com/ghodss/yaml`.

It can be installed via the **go** toolchain:

```shell
go get github.com/creack/yaml2json
yaml2json < glide.yaml > glide.json
```

or via **Docker**:

```shell
alias yaml2json='docker run -i --rm creack/yaml2json'
yaml2json < glide.yaml > glide.json
```

FYI, this **Docker** image contains only the statically linked, stripped down binary and weight only 3Mb!

```shell
$> docker images creack/yaml2json
REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
creack/yaml2json    latest              a8e3e1fff7bb        3 weeks ago         3.007 MB
```

### Caching

Now that we can have a **json** version of the **yaml** config, we can simply use **jq** in order to play with it.

With the new **vendor** model, the dependencies are now install as: `$APP_DIR/vendor/$DEP_PATH` rather than in the `GOPATH` directly.

Example: `yaml2json` is in `github.com/creack/yaml2json` and depends on `github.com/ghodss/yaml` so it will be installed as `github.com/creack/yaml2json/vendor/github.com/ghodss/yaml`

Another difficulty resides with the sub-packages, they are **glide** lists them as directory names under the parent's `imports` section. We need to use a bit more advanced **jq** query to construct the full list to be installed.

Let's see:

```dockerfile
FROM       golang:1.7
# Install yaml2json and jq.
RUN        apt-get update && apt-get install -y jq && go get github.com/creack/yaml2json
ENV        APP_DIR  github.com/org/myapp
ENV        APP_PATH $GOPATH/src/$APP_DIR
WORKDIR    $APP_PATH
ENTRYPOINT ["myapp"]
# Add glide lock file and precompile.
ADD        glide.lock $APP_PATH/glide.lock
ADD        vendor     $APP_PATH/vendor
RUN        yaml2json < glide.lock | \
           jq -r -c '.imports[], .testImports[] | {name: .name, subpackages: (.subpackages + [""])}' | \
           jq -r -c '.name as $name | .subpackages[] | [$name, .] | join("/")' | sed 's|/$||' | \
           while read pkg; do \
             echo "$pkg...";  \
             go install $APP_DIR/vendor/$pkg 2> /dev/null; \
           done

# Add App and install.
ADD        . $APP_PATH
RUN        go install
```

First, we convert the lock file to **json** using **yaml2json**, then we extract the main import list as well as the test import list from which we need the name and the sub-packages if any.
As some dependencies will not have sub-package, we manually add `+ [""]` to facilitate the next step.
Now that we have this list, we forge the full package names from the package list: we keep the "main" name and join it with the list of sub-packages (and `""` for the main package itself).
Finally, we trim down the trailing `/` if any and install each dependency.

## Alternative

Alternatively, instead of trying to pre-compile the dependencies, one could use the mount-bind feature of Docker in order to mount the local directory in a long running container and run the build/test there, which would allow to have the **native** caching of the **go** toolchain, but looses the reproducibility warranty of **Docker**.

# Conclusion

This method might not be the most "straight forward" one, but gives us the ability to quickly iterate over our code without worrying about the toolchain.

Bonus: the actual **Dockerfile** that I use at Agrarian Labs for all our micro services:

```dockerfile
FROM            golang:1.7
MAINTAINER      Guillaume J. Charmes <guillaume@leaf.ag>

# Install linters, coverage tools and test formatters.
RUN             go get github.com/alecthomas/gometalinter && gometalinter -i && \
                go get github.com/axw/gocov/... \
                       github.com/AlekSi/gocov-xml \
                       github.com/jstemmer/go-junit-report \
                       github.com/matm/gocov-html

# Disable CGO and recompile the stdlib.
ENV             CGO_ENABLED 0
RUN             go install -a -ldflags -d std

# Install jq and yaml2json for parsing glide.lock to precompile.
RUN             apt-get update && apt-get install -y jq
RUN             go get github.com/creack/yaml2json

ARG             APP_DIR

ENV             APP_PATH $GOPATH/src/$APP_DIR

WORKDIR         $APP_PATH

# Precompile deps.
ADD             glide.lock $APP_PATH/glide.lock
ADD             vendor     $APP_PATH/vendor
RUN             yaml2json < glide.lock | \
                jq -r -c '.imports[], .testImports[] | {name: .name, subpackages: (.subpackages + [""])}' | \
                jq -r -c '.name as $name | .subpackages[] | [$name, .] | join("/")' | sed 's|/$||' | \
                while read pkg; do \
                  echo "$pkg...";  \
                  go install -ldflags -d $APP_DIR/vendor/$pkg 2> /dev/null; \
                done

ADD             .          $APP_PATH

RUN             make install
```
