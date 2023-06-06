# Swift Compiler Indirect Macro Plugin

## What Does It Solve?

Typically a struct may have a lot of member due to the growth of an app.

```swift
struct Foo {

  var string: String
  
  var dictionary1: [String : Int]
  
  var dictionary2: [String : Int]
  
  var dictionary3: [String : Int]
  
  var dictionary4: [String : Int]
  
  // ...
  
}
```

This may cause bad performance when we are trying to copy them.

```swift
func fee(foo: Foo) {
  var copiedFoo1 = foo // retains ALL the heap storages in `Foo`
  copiedFoo1.dictionary1["key"] = 0 // copies the heap storage of dictionary1
  copiedFoo1.dictionary2["key"] = 1 // copies the heap storage of dictionary2
  copiedFoo1.dictionary3["key"] = 2 // copies the heap storage of dictionary3
  
}

func foe(foo: Foo) {
  let copiedFoo1 = foo // retains ALL the heap storages in `Foo`
  // do something with copiedFoo1 ...
  let copiedFoo2 = foo // retains ALL the heap storages in `Foo`
  // do something with copiedFoo2 ...
  let copiedFoo3 = foo // retains ALL the heap storages in `Foo`
  // do something with copiedFoo3 ...
}
```

By simply wrapping the type with `@Indirect` macro, you can improve the performance issue with copy-on-write behavior.

```swift
@Indirect // The only difference
struct Foo {

  var string: String
  
  var dictionary1: [String : Int]
  
  var dictionary2: [String : Int]
  
  var dictionary3: [String : Int]
  
  var dictionary4: [String : Int]
  
  // ...
  
}

func fee(foo: Foo) {
  var copiedFoo1 = foo // retains the copy-on-write storage only ONCE
  copiedFoo1.dictionary1["key"] = 0 // copies with copy-on-write heap storage, copies the heap storage of dictionary1
  copiedFoo1.dictionary2["key"] = 1 // copies the heap storage of dictionary2
  copiedFoo1.dictionary3["key"] = 2 // copies the heap storage of dictionary3
}

func foe(foo: Foo) {
  let copiedFoo1 = foo // retains the copy-on-write storage only ONCE
  // do something with copiedFoo1 ...
  let copiedFoo2 = foo // retains the copy-on-write storage only ONCE
  // do something with copiedFoo2 ...
  let copiedFoo3 = foo // retains the copy-on-write storage only ONCE
  // do something with copiedFoo3 ...
}
```
