---
title: JSON Date management in Golang
tags:
  - Golang
  - JSON
  - date
  - time
  - marshal
  - unmarshal
  - Parsing
categories:
  - Golang
draft: false
date: 2015-08-07 07:28:49
toc: true
thumbnail: images/jsondate.jpg
description: Use arbitrary date format with json marshal/unmarshal in Go.
---

## TL;DR

Arbitrary date unmarshal support + easily set marshal date format for both json and bson.
The code and examples can be found here: https://github.com/simplereach/timeutils.

### Small example

```go
package main

import (
        "encoding/json"
        "fmt"
        "os"

        "github.com/simplereach/timeutils"
)

type data struct {
        Time timeutils.Time `json:"time"`
}

func main() {
        var d data
        jStr := `{"time":"09:51:20.939152pm 2014-31-12"}`
        _ = json.Unmarshal([]byte(jStr), &d)
        fmt.Println(d.Time)

        d = data{}
        jStr = `{"time":1438947306}`
        _ = json.Unmarshal([]byte(jStr), &d)
        fmt.Println(d.Time)

        d.Time = d.Time.FormatMode(timeutils.RFC1123)
        _ = json.NewEncoder(os.Stdout).Encode(d)
}
```

## The Standard Library

Go provide an extensive support for dates/time in the standard library with the package `time`.

This allows to easily deal with dates, compare them or make operations on them as well as moving from a timezone to an other.

### Example

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	fmt.Printf("%s\n", time.Now().UTC().Add(-1 * time.Day))
}
```

### Formating

Within the `time.Time` object, there are easy ways to format the date:

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	now := time.Now().UTC()
	// Display the time as RFC3339
	fmt.Printf("%s\n", now.Format(time.RFC3339))
	// Display the timestamp
	fmt.Printf("%s\n", now.Unix())
	// Display only the hour/minute
	fmt.Printf("%s\n", now.Format("3:04PM"))
}
```

### Parsing

When it comes to parsing, once again, the standard library offers tools.

#### Parsing date string

```go
package main

import (
	"log"
	"fmt"
	"time"
)

func main() {
	t, err := time.Parse(time.RFC3339, "2006-01-02T15:04:05-07:00")
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("%s\n", t)
}
```

#### "Parsing" timestamp

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	now := time.Unix(1438947306, 0).UTC()
	fmt.Printf("%s\n", now)
}
```

This is great, but what if we don't know what time format we are expecting? i.e. user input or 3rd part API.

A solution would be to iterate through the available time formats until we succeed, but this is often cumbersome and unreliable.

#### Approxidate

The git library has this `Approxidate` component that parses arbitrary date format and there is a Golang binding so we can use it!

[https://godoc.org/github.com/simplereach/timeutils#ParseDateString](https://godoc.org/github.com/simplereach/timeutils#ParseDateString)

This expects a string as input and will do everything it can to properly yield a time object.

## Case of JSON Marshal/Unmarshal

### Unmarshal

Let's start with the unmarshal. What if we don't want to parse the time manually and let `json.Unmarshal` handle it? Let's try:

```go
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"time"
)

func main() {
	var t time.Time

	str := fmt.Sprintf("%q", time.Unix(1438947306, 123).Format(time.RFC3339))
	fmt.Printf("json string: %s\n", str)
	if err := json.Unmarshal([]byte(str), &t); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("result: %s\n", t.Format(time.RFC3339))
}
```

Magically, it works fine! This is great, isn't it?
But wait, the specs require us to send the date as RFC1123, is this going to work?
Let's try as well!

```go
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"time"
)

func main() {
	var t time.Time

	str := fmt.Sprintf("%q", time.Unix(1438947306, 123).Format(time.RFC1123))
	fmt.Printf("json string: %s\n", str)
	if err := json.Unmarshal([]byte(str), &t); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("result: %s\n", t.Format(time.RFC1123))
}
```

```
2009/11/10 23:00:00 parsing time ""Fri, 07 Aug 2015 11:35:06 UTC"" as ""2006-01-02T15:04:05Z07:00"": cannot parse "Fri, 07 Aug 2015 11:35:06 UTC"" as "2006"
```

Oups.

So it does not work, how can we work around this?

A solution would be to implement the `json.Unmarshaler` interface and handle our own parsing format, but we'll get to this.

### Marshal

Ok, we have our time object, and we want to send it as json. Nothing easier:

```go
package main

import (
	"encoding/json"
	"os"
	"time"
)

func main() {
	_ = json.NewEncoder(os.Stdout).Encode(time.Unix(1438947306, 0).UTC())
}
```

It works fine :) However, the client expects times as RFC1123, how can we set the format to `json.Marhsal`?

A way to do so would be to implement the `json.Marshaler` interface and handling our own formatting.

## Custom Marshal/Unmarshal

In order to tell Go to use a custom method for json marshal/unmarshal, one needs to implement the `json.Marshaler` and `json.Unmarshaler` interfaces.
As we can't do that on imported type `time.Time`, we need to create a custom type.

### Custom type

In order to create a custom type in Go, we simply do:

```go
type myTime time.Time
```

However, doing so "hides" all members and methods so we can't do things like this:

```go
var t myTime
t.UTC()
```

Which is pretty annoying as our goal is simply to override the JSON behavior. We still want our full blown object.
To do so, we'll use a struct with an anynomous member:

```go
type myTime struct {
	time.Time
}
```

This way, we can access all the methods of the nested time object.

### Unmarshal RFC1123

As we expect RFC1123, we need a custom parsing, so le'ts implement `json.Unmarshaler`.
Let's take our first RFC1123 example and improve it:

```go
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"time"
)

type myTime struct {
	time.Time
}

func (t *myTime) UnmarshalJSON(buf []byte) error {
	tt, err := time.Parse(time.RFC1123, strings.Trim(string(buf), `"`))
	if err != nil {
		return err
	}
	t.Time = tt
	return nil
}

func main() {
	var t myTime

	str := fmt.Sprintf("%q", time.Unix(1438947306, 123).Format(time.RFC1123))
	fmt.Printf("json string: %s\n", str)
	if err := json.Unmarshal([]byte(str), &t); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("result: %s\n", t.Format(time.RFC1123))
}
```

And now it works! We have a json unmarshal that supports RFC1123 instead of RFC3339!

To implment the `json.Unmarshaler` interface, we need to write the  `func (t *myTime) UnmarshalJSON(buf []byte) error` method.

This receives the json buffer and return an error. It is expected to set the parsed value to the receiver so it is important that the receiver is a pointer.

The first step, has we expect valid json is to trim down the `"` from the string, then we call the `time.Parse` and finally set the result to our object.

### Marshal RFC1123

Instead of the default RFC3339, let's have json encode our time as RFC1123:

```go
package main

import (
	"encoding/json"
	"os"
	"time"
)

type myTime struct {
	time.Time
}

func (t myTime) MarshalJSON() ([]byte, error) {
	return []byte(`"` + t.Time.Format(time.RFC1123) + `"`), nil
}

func main() {
	now := myTime{time.Unix(1438947306, 123)}
	_ = json.NewEncoder(os.Stdout).Encode(now)
}
```

Same idea as unmarshal. Here we only dump data so we don't want the receiver to be a pointer and we make sure that we return valid json wrapped in `"`.


## Going further

Changing the time format is great, but what if we need to move around dates as a timestamp integer? Or as a nanosecond timestamp? Or if we expect arbitrary format?

What if we have a REST API that need to move date between json and bson?

The `timeutils` library ([https://github.com/simplereach/timeutils](https://github.com/simplereach/timeutils)) offers a `Time` type that supports arbitrary time format via `aproxidate` as well as Timestamp and nanosecond precision both for marshal/unmarshal in json and bson.
