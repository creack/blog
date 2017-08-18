---
title: Selenium PhantomJS troubleshooting in Python
tags:
  - Python
  - Selenium
  - PhantomJS
  - Testing
  - Troubleshooting
categories:
  - Python
draft: fasle
date: 2015-06-10 09:01:11
toc: true
thumbnail: images/selenium-logo.png
description: Identify and fix issues in PhantomJS with Python.
---

# The problem

After couple of minutes running, the machines crashes. Can't ssh, can't do anything.
On an other machine, it works fine though...

So what is going on?

# Troubleshoot

After digging a bit, I figured that the machine working was running the pip package `selenium==2.45.0` and the faulty one `selenium==2.46.0`.

The python, node, phantomjs and the rest of the pip freeze are the same.

# Isolating the issue

First step: trim down what is running. Doing this gave me more time on the machine before it crashes and I noticed that there is a lot of phantomjs process running, which doesn't seem right.

Knowing that, I tried a simple script using a single instance of selenium to see what happen.

The script (from https://realpython.com/blog/python/headless-selenium-testing-with-python-and-phantomjs/):

```python
from selenium import webdriver
driver = webdriver.PhantomJS()
driver.set_window_size(1120, 550)
driver.get("https://duckduckgo.com/")
driver.find_element_by_id('search_form_input_homepage').send_keys("realpython")
driver.find_element_by_id("search_button_homepage").click()
print driver.current_url
driver.quit()
```

Nothing too complex, we instantiate the webdriver PhantomJS (which will cause the phantomjs process to start), get the duckduckgo page and display the URL.

Doing this without `driver.quit()` indeed start the `phantomjs` process, but the interesting part is that it does so has a child of `node`.
When calling `driver.quit()`, the `node` process does exit properly, but the `phantomjs` one does not.
Doing the same test on `selenium==2.45.0` result in `driver.quit()` correctly killing `node` and `phantomjs`

# Solution

Revert to 2.45 :):
 `pip install selenium==2.45.0`.

# More

At first, I though selenium tried to isolate the phantomjs process in its own process session and/or group, but after looking more closely, it appears that it is not the case.

On 2.46.0, running the test script before the quit:

```bash
$> ps  xao comm,pid,ppid,pgid,sid | grep phantom
phantomjs        84808  84806  84803  57599
$> ps  xao comm,pid,ppid,pgid,sid | grep node
node             84806  84803  84803  57599
```

So we do have `node` which is the direct parent of `phantomjs` and they are both on the same session and group.

After running `driver.quit()`:

```bash
$> ps  xao comm,pid,ppid,pgid,sid | grep phantom
phantomjs        84808  1  84803  57599
$> ps  xao comm,pid,ppid,pgid,sid | grep node
```

Sending a `SIGTERM` to `phantomjs` does exit the process, so it means that `selenium` does not `kill` node with `SIGTERM` or any "hard" signal.

It would be interesting to dig into how `selenium` tells `node` to quit.
