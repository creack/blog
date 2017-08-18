---
title: Scope and Shadowing in Go
tags:
  - Golang
  - Shadowing
categories:
  - Golang
draft: false
date: 2015-07-08 18:02:31
toc: true
thumbnail: images/woman-shadow1.jpg
description: Understand scopes and variable shadowing in Go.
---

Variable shadowing can be confusing in Go, let's try to clear it up.

# Case of errors

Without even maybe knowing it, you have been playing with shadowing with your errors.
Consider the following code:

```go
package main

import (
	"io/ioutil"
	"log"
)

func main() {
	f, err := ioutil.TempFile("", "")
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()

	if _, err := f.Write([]byte("hello world\n")); err != nil {
		log.Fatal(err)
	}
}
```

Notice that we first create two variable: **f** and **err** from the **TempFile** function.
We then call **Write** discarding the number of bytes written. We make the function call it within the **if** statement.
Let's compile, it work fine.

Now, the same code with the **Write** call outside the if:

```go
package main

import (
	"io/ioutil"
	"log"
)

func main() {
	f, err := ioutil.TempFile("", "")
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()

	_, err := f.Write([]byte("hello world\n"))
	if err != nil {
		log.Fatal(err)
	}
}
```

Now, compilation fails: `main.go:15: no new variables on left side of :=`

So what happened?

Note that we call **Write** with `:=`, which means that we create a new variable **err**. In the second example, it is pretty obvious, **err** already exists so we can't redeclare it. But then why did it work the first time?
Because in Go, variables are local to their scope. In the first example, we actually *shadowed* **err** within the **if** scope.

# Simple Demo

```go
package main

func main() {
	var err error
	_ = err
	var err error
	_ = err
}
```

This will obviously fail, however, if we scope the second **err**, it will work!

```go
package main

func main() {
	var err error
	_ = err
	{
		var err error
		_ = err
	}
}
```

# Package Shadowing

Consider the following code:

```go
package main

import "fmt"

func Debugf(fmt string, args ...interface{}) {
	fmt.Printf(fmt, args...)
}
```

At first, it looks decent. We call **Printf** from the `fmt` package and pass the **fmt** variable to it.

**WRONG**

the `fmt string` from the function declaration actually *shadows* the package and is now "just" a variable. The compiler will complain:
We need to use a different variable name conserve access to the `fmt` package.

# Global scope

Something to take into consideration is that a function is already a "sub scope", it is a scope within the global scope. This means that any variable you declare within a function can *shadow* something from the global scope.

Just as we saw before that a variable can *shadow* a package, the concept is the same for global variables and functions.

# Type enforcement

Just like we can shadow a package with a variable or a function, we also can shadow a variable by a new variable of any type. Shadowed variables does not need to be from the same type. This example compiles just fine:

```go
package main

func main() {
	var a string
	_ = a
	{
		var a int
		_ = a
	}
}
```

# Closures

The scope is very important when using embeded functions. Any variable used in a function and not declared are references to the upper scope ones.
Well known example using **goroutines**:

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	for _, elem := range []byte{'a', 'b', 'c'} {
		go func() {
			fmt.Printf("%c\n", elem)
		}()
	}
	time.Sleep(1e9) // Sleeping to give time to the goroutines to be executed.
}
```

The result is:

```shell
c
c
c
```

Which is not really what we wanted.
This is because the **range** changes **elem** which is referenced in the goroutine, so on short lists, it will always display the last element.

To avoid this, there are two solutions:

- Passing variable to the function

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	for _, elem := range []byte{'a', 'b', 'c'} {
		go func(char byte) {
			fmt.Printf("%c\n", char)
		}(elem)
	}
	time.Sleep(1e9)
}
```

- Create a copy of the variable in the local scope

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	for _, elem := range []byte{'a', 'b', 'c'} {
		char := elem
		go func() {
			fmt.Printf("%c\n", char)
		}()
	}
	time.Sleep(1e9)
}
```

In both case we get our expected result:

```shell
a
b
c
```

When we pass the variable to the function, we actually send a copy of the variable to the function which receives it as **char**. Because every goroutines gets its own copy, there is no problem.
When we make a copy of the variable,  we create a new variable and assigns the value of **elem** to it.
We do this at each iteration, which means that for each steps, we create a new variable which the goroutine get a reference to. Each goroutine has a reference to a different variable and it work fine as well.

Now, as we know that we can *shadow* variable, why bother change the name? We can simply use the same name knowing that it will shadow the upper scope:

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	for _, elem := range []byte{'a', 'b', 'c'} {
		go func(elem byte) {
			fmt.Printf("%c\n", elem)
		}(elem)
	}
	time.Sleep(1e9)
}
```

```go
package main

import (
	"fmt"
	"time"
)

func main() {
	for _, elem := range []byte{'a', 'b', 'c'} {
		elem := elem
		go func() {
			fmt.Printf("%c\n", elem)
		}()
	}
	time.Sleep(1e9)
}
```

When we pass the variable to the function, the same thing happens, we pass a copy of the variable to the function which gets it with the name **elem** with the correct value. From this scope, because the variable is shadowed, we can't impact the **elem** from the upper scope and any change made will be applied only within this scope.
When we make a copy of the variable,  same as before: we create a new variable and assigns the value of **elem** to it. In this case, that new variable happens to have the same name as the other one but the idea stays the same: new variable + assign value. As we create a new variable within the scope with the same name we effectively *shadow* that variable while keeping it's value.

# Case of `:=`

When using `:=` with multiple return functions (or type assertion, channel receive and map access), we can endup with 3 variables out of 2 statements:

```go
package main

func main() {
	var iface interface{}

	str, ok := iface.(string)
	if ok {
		println(str)
	}
	buf, ok := iface.([]byte)
	if ok {
		println(string(buf))
	}
}
```

In this situation, **ok** does not get *shadowed*, it simply gets overridden. Which is why **ok** can't change type.
Doing so in a scope, however, would *shadow* the variable and allow for a different type:

```go
package main

func main() {
	var m = map[string]interface{}{}

	elem, ok := m["test"]
	if ok {
		str, ok := elem.(string)
		if ok {
			println(str)
		}
	}
}
```


# Conclusion

*Shadowing* can be very useful but needs to be something to keep in mind to avoid unexpected behavior.
It is of course on a case basis, it often helps readability and safety, but can also reduce it.

In the example of the goroutines, because it is a trivial example, it is more readable to *shadow*, but in a more complex situation, it might be best to use different names to make sure what you are modifying.
In an other hand, however, especially for errors, it is a very powerful tool.
Going back to my first example:

```go
package main

import (
	"io/ioutil"
	"log"
)

func main() {
	f, err := ioutil.TempFile("", "")
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()

	if _, err := f.Write([]byte("hello world\n")); err != nil {
		err = nil
	}
	// err is still the one form TempFile
}
```

In this situation, shadowing **err** within the gives a warranty that previous errors will not be impacted whereas if with the same code we used `=` instead of `:=` in the **if**, it would not have *shadowed* the variable but override the value of the error.
