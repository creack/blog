---
title: How to properly contribute to a Go project
tags:
  - Golang
  - Github
  - Open Source
categories:
  - Golang
draft: false
date: 2014-11-15 06:09:51
toc: false
thumbnail: images/gopher.png
description: Properly setup your environment and git fork to contribute to Golang open source projects.
---

Golang as a very strict directory hierarchy on which the builder (and more generally the Go tools) rely on.

I am often asked what is the proper way to contribute to a Go project.

# Use cases

- Contributing to a random Go project
- Working as a team on a "central" repository
- Contributing to a Go project with sub-repositories

# The problem

The issue is that when you `go get` a project, it ends up in (with github) `$GOPATH/src/github.com/creack/termios`.

If you fork the project, you will have `github.com/<myuser>/termios`.

If you `go get` that forked URL, it will work fine. However, if you are dealing with a library that needs to be imported, then you need to update the import paths. Even worse, if the project has sub-repositories, then all import paths will target the original project.

# Solution

Use your fork only as remote placeholder, do not use it locally.
Use the remote feature of git.

Example for user `gcharmes` trying to contribute to `creack/termios`

1. Fork the project
2. get the original one `go get github.com/creack/termios`
3. cd `$GOPATH/src/github.com/creack/termios`
4. Add the new remote: `git remote add gcharmes git@github.com:gcharmes/termios.git`
5. Fetch everything from github `git fetch --all`
6. Checkout in a new branch `git checkout -b mybranch`
6. Contribute, as we are on the original checkout, all the paths are correct
7. Commit and push `git commit -p && git push gcharmes mybranch`
8. Go to github and create the pull request.


That's it! This work if you want to fork a project and use it transparentely, it works when working on sub-packages, it works everywhere :)

Extra tip: use Godeps (https://github.com/tools/godep). When using external dependencies, you should vendor them.
It as also the advantage to backup your local version, so if you submitted a PR that didn't get accepted yet, you still can commit to your own project using your commit for that dependency.
