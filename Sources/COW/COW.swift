/// A marker protocol marks the type is a copy-on-write user storage
@_marker public protocol CopyOnWriteStorage {
  
}

/// Marks a `struct` to be copy-on-writable
///
/// - Warning: Use `@COW` in a `#if ... #else ... #end` config is an
/// undefined behavior.
///
@attached(member, names: arbitrary)
@attached(memberAttribute)
public macro COW() =
  #externalMacro(module: "COWMacros", type: "COWMacro")

/// Marks a `struct` to be copy-on-writable and specifies the storage
/// variable name.
///
/// - Parameter storageName: The name of the copy-on-write storage.
///
/// - Warning: Use `@COW` in a `#if ... #else ... #end` config is an
/// undefined behavior.
///
@attached(member, names: arbitrary)
@attached(memberAttribute)
public macro COW(storageName: String) =
  #externalMacro(module: "COWMacros", type: "COWMacro")

/// Marks a property in a `@COW` makred `struct` should be taken into
/// consideration as a part of the copy-on-write behavior.
///
/// - Note: This macro is makred along side while expanding `@COW` on a
/// `struct`. You don't need to mark this on a property by yourself in most
/// of the time.
///
/// - Warning: Use `@COWIncluded` in a `#if ... #else ... #end` config is an
/// undefined behavior.
///
@attached(accessor)
public macro COWIncluded(storageName: String) =
  #externalMacro(module: "COWMacros", type: "COWIncludedMacro")

/// Marks a property in a `@COW` makred `struct` should not be taken into
/// consideration as a part of the copy-on-write behavior.
///
/// - Warning: Use `@COWExcluded` in a `#if ... #else ... #end` config is an
/// undefined behavior.
///
@attached(peer)
public macro COWExcluded() =
  #externalMacro(module: "COWMacros", type: "COWExcludedMacro")

/// Mark a subtype in a `@COW` makred `struct` as the storage to use for
/// implementing copy-on-write behavior.
///
/// Developers can use this macro to make their `@COW` marked types to
/// conform protocols like `Equatable` or using property wrappers or
/// other attached macros together.
///
/// Before:
///
/// ```swift
/// @propertyWrapper
/// struct Capitalized {
///   var wrappedValue: String {
///     didSet {
///       self.wrappedValue = wrappedValue.capitalized
///     }
///   }
/// }
///
/// struct Values: Equatable {
///
///   var number: Int
///
///   @Capitalized
///   var string: String
///
///   var bool: Bool
///
/// }
/// ```
///
/// After:
///
/// ```swift
/// @COW
/// struct Values: Equatable {
///
///   @COWStorage
///   struct Storage: Equatable {
///
///     @Capitalized
///     var string: String
///
///   }
///
///   var number: Int = 0
///
///   @COWExcluded
///   var string: String {
///     get {
///       _$storage.string
///     }
///     set {
///       _$storage.string = newValue
///     }
///   }
///
///   var bool: Bool = false
///
/// }
/// ```
///
/// - Warning: Use `@COWStorage` in a `#if ... #else ... #end` config is
/// an undefined behavior.
///
@attached(extension, conformances: CopyOnWriteStorage)
public macro COWStorage() =
  #externalMacro(module: "COWMacros", type: "COWStorageMacro")

public enum COWStoragePropertyKeyword: String {
  case `let` = "let"
  case `var` = "var"
}

/// Adds a property to the copy-on-write storage.
///
/// The `@COW` macro would compute which properties are required to add to
/// the copy-on-write storage and apply this macro to the storage on behalf
/// of you. When the properties in your `@COW` applied struct changed, the
/// `@COWStorageAddProperty`s applied on the copy-on-write storage get
/// changed automatically.
///
/// - Note: You don't have to apply this macro to the copy-on-write storage
/// directly.
///
@attached(member, names: arbitrary)
public macro COWStorageAddProperty(
  keyword: COWStoragePropertyKeyword,
  name: String,
  type: String,
  initialValue: String
) = #externalMacro(module: "COWMacros", type: "COWStorageAddPropertyMacro")

@attached(member, names: arbitrary)
public macro COWStorageAddProperty(
  keyword: COWStoragePropertyKeyword,
  name: String,
  type: String
) = #externalMacro(module: "COWMacros", type: "COWStorageAddPropertyMacro")

@attached(member, names: arbitrary)
public macro COWStorageAddProperty(
  keyword: COWStoragePropertyKeyword,
  name: String,
  initialValue: String
) = #externalMacro(module: "COWMacros", type: "COWStorageAddPropertyMacro")

/// Marks a static method in a struct that has applied the `@COW` macro to
/// indicate the method is a user defined static make storage method.
///
@attached(peer)
public macro COWMakeStorage()
  = #externalMacro(module: "COWMacros", type: "COWMakeStorageMacro")

@propertyWrapper
@frozen
public struct _Box<Contents: CopyOnWriteStorage> {
  
  public var _buffer: ManagedBuffer<Contents, Void>
  
  @inlinable
  public init(wrappedValue: Contents) {
    _buffer = .create(minimumCapacity: 0) { _ in
      return wrappedValue
    }
  }
  
  @inlinable
  public var wrappedValue: Contents {
    @_effects(readonly)
    _read {
      yield _buffer.header
    }
    @_effects(readwrite)
    _modify {
      _makeUniqueBufferIfNeeded()
      yield &_buffer.header
    }
  }
  
  @inlinable
  public var projectedValue: _Box {
    @_effects(readonly)
    _read {
      yield self
    }
    @_effects(readwrite)
    _modify {
      _makeUniqueBufferIfNeeded()
      yield &self
    }
  }
  
  @inlinable
  @_semantics("array.make_mutable")
  @_effects(notEscaping self.**)
  public mutating func _makeUniqueBufferIfNeeded() {
    guard _slowPath(!_isUnique_native(&_buffer)) else {
      return
    }
    _buffer = .create(minimumCapacity: 1) { [_buffer] _ in
      return _buffer.header
    }
  }
  
}

extension _Box: Equatable where Contents: Equatable {
  
  @inlinable
  public static func == (lhs: Self, rhs: Self) -> Bool {
    return lhs.wrappedValue == rhs.wrappedValue
  }
  
}

extension _Box: Hashable where Contents: Hashable {
  
  @inlinable
  public func hash(into hasher: inout Hasher) {
    hasher.combine(wrappedValue)
  }
  
}

extension _Box: Codable where Contents: Codable {
  
  @inlinable
  public func encode(to encoder: Encoder) throws {
    try wrappedValue.encode(to: encoder)
  }
  
  @inlinable
  public init(from decoder: Decoder) throws {
    self.init(wrappedValue: try Contents(from: decoder))
  }
  
}

// Idea of workaround credits to 
// https://github.com/JosephDuffy/HashableMacro/commit/250787664a63ceff83c1c9b5e30e574ada568f2f
#if swift(<5.9.2)
public protocol COWStorageEquatableWorkaround {
  static func equalsWorkaround(lhs: Self, rhs: Self) -> Bool
}

public extension Equatable where Self: COWStorageEquatableWorkaround {
  static func == (lhs: Self, rhs: Self) -> Bool {
    equalsWorkaround(lhs: lhs, rhs: rhs)
  }
}
#endif
