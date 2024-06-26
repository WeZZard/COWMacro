# Swift Compiler Copy-on-Write Macro Plugin

## What Does It Solve?

A Swift macro named `@COW` that improves a Swift `struct` copy performance N
times where N is the count of the heap storages in the struct.

For example, the `@COW` could improve the copy performance of the following
struct 4 times. Because `String`, `Array`, `Set` and `Dictionary` both employ a
heap storage to store the contents.

```swift
struct Foo {
  
  var string: String
  
  var array: [Int]
  
  var set: Set<Int>
  
  var dict: Dictionary<String : Int>
  
}
```

## Usage

### Quick Start

You can just attach `@COW` to a struct to make a struct adopt copy-on-write
behavior.

```swift
@COW
struct Foo {
  
  var string: String
  
  var array: [Int]
  
  var set: Set<Int>
  
  var dict: Dictionary<String : Int>
  
}
```

### Dealing with Explicit Initializers

Sometimes you may have explicit initializers declared. To make structs like this
compilable, you have to explicitly help initialize with copy-on-write storage.

```swift
struct Foo {
  
  var string: String
  
  var array: [Int]
  
  var set: Set<Int>
  
  var dict: Dictionary<String : Int>
  
  init(myParameters: MyParameters) {
    ...
  }
  
}
```

Once attach `@COW` macro to your struct, the Xcode would notice you to insert
the copy-on-write storage initialization at the beginning of the explicit init.
You can click that fix-it message to apply the expression auto generated by the
COW macro compiler plugin and then fill the blanks in the expression:

```swift
@COW
struct Foo {
  
  var string: String
  
  var array: [Int]
  
  var set: Set<Int>
  
  var dict: Dictionary<String : Int>
  
  init(myParameters: MyParameters) {
    self._$storage = _$COWStorage(string: ..., array: ..., set: ..., dict: ...)
    ...
  }
  
}
```

### Dealing With lazy Properties

Sometimes you may have lazy properties in your struct. This would not compile
with `@COW` macro because `@COW` macro could rewrite your property into a
computed property but the lazy keyword requires the property to be stored.

```swift
struct Foo {
  
  lazy var name: String = makeName()
  
  ...
  
}
```

However, with `@COWStorage` macro and a custom storage type, we can work this
around:

```swift
@COW
struct Foo {

  @COWStorage
  struct MyStorage {
  
      lazy var name: String = makeName()
  
  }
  
  @COWExcluded
  var name: String {
    get {
      return _$storage.name
    }
    set {
      _$storage.name = newValue
    }
  }
  
  ...
  
}
```

### Dealing With Property Wrappers

Sometimes you may have property wrappers in your struct. This would not compile
with `@COW` macro because `@COW` macro could rewrite your property into a
computed property but the property wrapper requires the property to be stored.

```swift
@propertyWrapper
struct Capitalized {
  ...
}

struct Foo {
    
  @Capitalized
  var name: String
  
  ...
  
}
```

However, with `@COWStorage` macro and a custom storage type, we can work this
around:

```swift
@COW
struct Foo {

  @COWStorage
  struct MyStorage {
  
      @Capitalized
      var name: String
  
  }
  
  @COWExcluded
  var name: String {
    get {
      return _$storage.name
    }
    set {
      _$storage.name = newValue
    }
  }
  
  ...
  
}
```

### Dealing With Storage Name Conflicts

There could be other macros that declares a `_$storage` in your struct. The
`@COW` macro has taken this into consideration: you can use the argument
`storageName` to specify the name of the storage generated and used by the
`@COW` macro.

```swift
@COW(storageName: "_myCOWStorage")
@OtherMacroDeclares_$storage
struct Foo {
  
  var string: String
  
  var array: [Int]
  
  var set: Set<Int>
  
  var dict: Dictionary<String : Int>
  
}
```

## How Does It Work?

This macro forwards the stored properties in a struct to a heap storage that
adopts copy-on-write behavior. The heap storage is composited by a content type
which names `struct _$COWStorage` by default and a property wrapper called
`@COW._Box` that adopts copy-on-write behavior and implements the heap store.

The original:

```swift
struct Foo {
  
  var string: String
  
  var array: [Int]
  
  var set: Set<Int>
  
  var dict: Dictionary<String : Int>
  
}
```

After expansion:

```swift
@COW
struct Foo {

  // The content type
  @COWStorage
  struct _$COWStorage {
  
    var string: String
  
    var array: [Int]
  
    var set: Set<Int>
  
    var dict: Dictionary<String : Int>
  
  }
  
  // The storage member compsited with copy-on-write box property wrapper and
  // the content type
  @COW._Box
  var _$storage: _$COWStorage
  
  @COWIncluded
  var string: String {
    get {
        _$storage.string
    }
    set {
        _$storage.string = newValue
    }
  }
  
  @COWIncluded
  var array: [Int] {
    get {
        _$storage.array
    }
    set {
        _$storage.array = newValue
    }
  }
  
  @COWIncluded
  var set: Set<Int> {
    get {
        _$storage.set
    }
    set {
        _$storage.set = newValue
    }
  }
  
  @COWIncluded
  var dict: Dictionary<String : Int> {
    get {
        _$storage.dict
    }
    set {
        _$storage.dict = newValue
    }
  }
  
}
```

## Contribution

The project is open for contribution; however, please be mindful of the
[coding standards](./CODE-STYLE.md). Paired test cases are also required
for bugfix and feature contributions.

## License

MIT
