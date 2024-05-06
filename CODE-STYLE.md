# Code Style of This Project

Essentially, we adhere to the following guidelines from Apple with several
additions.

- [API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)

## Project Specific Additions

1. Explicitly Marks The Access Control For Each Declaration in Library Targets

Explicit access control is required for declarations in library targets like
`COW` and `COWMacros`.

Examples:

```swift
// ✅
public func fee() {

}

// ❌
func fee() {

}
```

Explicit access control prevents people from abusing or misusing variables,
structs, classes or any other declarations which may introduce potential bugs.

Since library authors are set to aim at giving solutions that developers in
large amount of places. Having a clarity regarding the scope of each declaration
of the program is essential for achieving this goal. Explicitly marking the
access control may be a small effort once a library author has this clarity in
mind.

Here are extended examples:

```swift
// ✅
internal class Foe {

}

// ❌
class Foe {

}

// ✅
private class Fum {

}

// ❌
class Fum {

}
```
