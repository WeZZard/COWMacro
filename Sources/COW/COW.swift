
/// A marker protocol marks the type is copy-on-writable
@_marker public protocol CopyOnWritable {
  
}

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
@attached(conformance)
public macro COW(_ storageVariableName: String = "_$storage") =
  #externalMacro(module: "COWMacros", type: "COWMacro")

/// Marks a property in a `@COW` makred `struct` should be taken into
/// consideration as a part of the copy-on-write behavior.
///
/// - Note: This macro is makred as long as you marked `@COW` to a struct.
/// You don't need to mark this on a property by yourself in most of the
/// time.
///
/// - Warning: Use `@COWIncluded` in a `#if ... #else ... #end` config is an
/// undefined behavior.
///
@attached(accessor)
public macro COWIncluded() =
  #externalMacro(module: "COWMacros", type: "COWIncludedMacro")

public class ExcludeBehavior {
  
  public static let noCOWCodeGeneration: ExcludeBehavior
    = NoCOWCodeGenerationExcludeBehavior()
  
  public static func forwardToStorage<
    Storage: CopyOnWriteStorage,
    Member
  >(keyPath: KeyPath<Storage, Member>) -> ExcludeBehavior {
    return ForwardToStorageExcludeBehavior(keyPath: keyPath)
  }
  
  @inlinable
  public init() { }
  
}

public final class NoCOWCodeGenerationExcludeBehavior: ExcludeBehavior {
  
  @inlinable
  public override init() { }
  
}

public final class ForwardToStorageExcludeBehavior<
  Storage: CopyOnWriteStorage,
  Member
>: ExcludeBehavior {
  
  public let keyPath: KeyPath<Storage, Member>
  
  @inlinable
  public init(keyPath: KeyPath<Storage, Member>) {
    self.keyPath = keyPath
  }
  
}

/// Marks a property in a `@COW` makred `struct` should not be taken into
/// consideration as a part of the copy-on-write behavior.
///
/// - Note: This macro is makred as long as you marked
/// `@COWStorageForwarded` to a struct. You don't need to mark this on a
/// property by yourself in most of the time.
///
/// - Warning: Use `@COWExcluded` in a `#if ... #else ... #end` config is an
/// undefined behavior.
///
@attached(accessor)
public macro COWExcluded(_ behavior: ExcludeBehavior = .noCOWCodeGeneration) =
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
///   var number: Int
///
///   @COWExcluded(.forwardToStorage(keyPath: Storage.string))
///   var string: String
///
///   var bool: Bool
///
/// }
/// ```
///
/// - Warning: Use `@COWStorage` in a `#if ... #else ... #end` config is
/// an undefined behavior.
///
@attached(conformance)
public macro COWStorage() =
  #externalMacro(module: "COWMacros", type: "COWStorageMacro")

@attached(accessor)
public macro COWStorageAddProperty(varDeclSyntax: String)
  = #externalMacro(module: "COWMacros", type: "COWStorageAddPropertyMacro")

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
    _read {
      yield UnsafePointer(_buffer.withUnsafeMutablePointerToHeader({$0})).pointee
    }
    _modify {
      _makeUniqueBufferIfNeeded()
      yield &_buffer.withUnsafeMutablePointerToHeader({$0}).pointee
    }
  }
  
  @inlinable
  public mutating func _makeUniqueBufferIfNeeded() {
    guard !isKnownUniquelyReferenced(&_buffer) else {
      return
    }
    _buffer = .create(minimumCapacity: 1) { _ in
      return self.wrappedValue
    }
  }
  
}
