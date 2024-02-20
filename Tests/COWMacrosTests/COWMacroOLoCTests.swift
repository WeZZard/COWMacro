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
  
  /// struct with var binding properties having initializers.
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
  func testStructWithVarBindingPropertyHavingInitializer() {
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
          _read {
            yield _$storage.value
          }
          _modify {
            yield &_$storage.value
          }
        }
        struct _$COWStorage: COW.CopyOnWriteStorage {
          var value: Int = 0
        }
        @COW._Box
        var _$storage: _$COWStorage = _$COWStorage()
      
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  /// struct with let binding properties having initializers.
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
  ///   valetr value: Int = 0
  ///
  /// }
  /// ```
  ///
  func testStructWithLetBindingPropertyHavingInitializer() {
    assertMacroExpansion(
      """
      @COW
      struct Foo {
      
        let value: Int = 0
      
      }
      """,
      expandedSource:
      """
      
      struct Foo {
      
        let value: Int = 0 {
          _read {
            yield _$storage.value
          }
        }
        struct _$COWStorage: COW.CopyOnWriteStorage {
          let value: Int = 0
        }
        @COW._Box
        var _$storage: _$COWStorage = _$COWStorage()
      
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  /// struct with var binding properties having type annotations only.
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
  func testStructWithVarBindingPropertyHavingTypeAnnotationOnly() {
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
          _read {
            yield _$storage.value
          }
          _modify {
            yield &_$storage.value
          }
        }
        struct _$COWStorage: COW.CopyOnWriteStorage {
          var value: Int
        }
        @COW._Box
        var _$storage: _$COWStorage
        init(value: Int) {
          self._$storage = _$COWStorage(value: value)
        }
      
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  /// struct with let binding properties having type annotations only.
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
  func testStructWithLetBindingPropertyHavingTypeAnnotationOnly() {
    assertMacroExpansion(
      """
      @COW
      struct Foo {
      
        let value: Int
      
      }
      """,
      expandedSource:
      """
      
      struct Foo {
      
        let value: Int {
          _read {
            yield _$storage.value
          }
        }
        struct _$COWStorage: COW.CopyOnWriteStorage {
          let value: Int
        }
        @COW._Box
        var _$storage: _$COWStorage
        init(value: Int) {
          self._$storage = _$COWStorage(value: value)
        }
      
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  /// Does not break the behavior of auto synthesizing protocols.
  ///
  /// `Hashable`, `Codeable` shall also work.
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
          _read {
            yield _$storage.value
          }
          _modify {
            yield &_$storage.value
          }
        }
        struct _$COWStorage: COW.CopyOnWriteStorage, Equatable {
          var value: Int = 0
        }
        @COW._Box
        var _$storage: _$COWStorage = _$COWStorage()
      
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  /// Do not expand on static properties.
  ///
  /// The original struct:
  ///
  /// ```
  /// struct Foo {
  ///
  ///   static var value: Int
  ///   var baz: Int
  ///
  /// }
  /// ```
  ///
  func testStructWithStaticProperties() {
    assertMacroExpansion(
      """
      @COW
      struct Foo {
      
        static var bar: Int
        var baz: Int
      
      }
      """,
      expandedSource:
      """
      
      struct Foo {
      
        static var bar: Int
        var baz: Int {
          _read {
            yield _$storage.baz
          }
          _modify {
            yield &_$storage.baz
          }
        }
        struct _$COWStorage: COW.CopyOnWriteStorage {
          var baz: Int
        }
        @COW._Box
        var _$storage: _$COWStorage
        init(baz: Int) {
          self._$storage = _$COWStorage(baz: baz)
        }
      
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }

}

