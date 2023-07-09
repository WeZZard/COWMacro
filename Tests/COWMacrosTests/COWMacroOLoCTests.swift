@_implementationOnly import SwiftSyntaxMacros
@_implementationOnly import SwiftSyntaxMacrosTestSupport
@_implementationOnly import XCTest

@testable import COWMacros

/// `OLoC` means one line of code.
///
final class COWMacroOLoCTests: XCTestCase {
  
  /// `@COW` should not have effects on an empty struct.
  ///
  /// ```
  /// The original struct:
  ///
  /// struct Foo {
  ///
  /// }
  /// ```
  ///
  func testEmptyStruct() {
    assertMacroExpansion(
      """
      @COW
      struct Foo {
      }
      """,
      expandedSource: """
      
      struct Foo {
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  /// struct with properties having initializers.
  ///
  /// When the struct has no explicit initializers and the implicit
  /// initializer has no argument, we don't have to generate the
  /// initializer.
  ///
  /// The original struct:
  ///
  /// ```
  /// struct Foo {
  ///
  ///   var value: Int = 0
  ///
  /// }
  /// ```
  ///
  func testStructWithPropertyHavingInitializer() {
    assertMacroExpansion(
      """
      @COW
      struct Foo {
      
        var value: Int = 0
      
      }
      """,
      expandedSource:
      """
      
      struct Foo {
      
        var value: Int = 0 {
          get {
            return _$storage.value
          }
          set {
            _$storage.value = newValue
          }
        }
        struct __macro_local_7StoragefMu_: COW.CopyOnWriteStorage {
        
          var value: Int = 0
        }
        @COW._Box
        var _$storage: __macro_local_7StoragefMu_ = __macro_local_7StoragefMu_()
      
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  /// struct with properties having type annotations only.
  ///
  /// When the struct has no explicit initializers and the implicit
  /// initializer has arguments, we have to generate the make storage method
  /// and an explicit initializer.
  ///
  /// The original struct:
  ///
  /// ```
  /// struct Foo {
  ///
  ///   var value: Int
  ///
  /// }
  /// ```
  ///
  func testStructWithPropertyHavingTypeAnnotationOnly() {
    assertMacroExpansion(
      """
      @COW
      struct Foo {
      
        var value: Int
      
      }
      """,
      expandedSource:
      """
      
      struct Foo {
      
        var value: Int {
          get {
            return _$storage.value
          }
          set {
            _$storage.value = newValue
          }
        }
        struct __macro_local_7StoragefMu_: COW.CopyOnWriteStorage {
        
          var value: Int
        }
        @COW._Box
        var _$storage: __macro_local_7StoragefMu_
        static func _$makeStorage(value: Int) -> __macro_local_7StoragefMu_ {
          return __macro_local_7StoragefMu_(
              value: value
          )
        }
        init(value: Int) {
          self._$storage = Self._$makeStorage(
              value: value
          )
        }
      
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  /// Does not break the behavior of auto synthesizing protocols.
  ///
  /// `Hashable`, `Comparable`, `Codeable` shall also work.
  ///
  /// The original struct:
  ///
  /// ```
  /// struct Foo: Equatable {
  ///
  ///   var value: Int = 0
  ///
  /// }
  /// ```
  ///
  func testStructWithPropertyAndConformsToAutoSynthesizingProtocols() {
    assertMacroExpansion(
      """
      @COW
      struct Foo: Equatable {
      
        var value: Int = 0
      
      }
      """,
      expandedSource:
      """
      
      struct Foo: Equatable {
      
        var value: Int = 0 {
          get {
            return _$storage.value
          }
          set {
            _$storage.value = newValue
          }
        }
        struct __macro_local_7StoragefMu_: COW.CopyOnWriteStorage, Equatable {
        
          var value: Int = 0
        }
        @COW._Box
        var _$storage: __macro_local_7StoragefMu_ = __macro_local_7StoragefMu_()
      
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }

}

