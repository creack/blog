---
title: Test Diagrams
draft: false
date: 2017-08-18
---

```sequence
Andrew->China: Says Hello
Note right of China: China thinks\nabout it
China-->Andrew: How are you?
Andrew->>China: I am good thanks!
France->Germany: says lol
```

```sequence
John->China: Says Hello
Note right of China: China thinks\nabout it
China-->Andrew: How are you?
Andrew->>China: I am good thanks!
France->Henry: says lol
```

```flow
st=>start: Start
e=>end
op=>operation: My Operation
op2=>operation: My Opera2tion
cond=>condition: Yes or No or Maybe?
st->op->cond
st->op2->e
cond(maybe)->op2
cond(yes)->e
cond(no)->op
```
