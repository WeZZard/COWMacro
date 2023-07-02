@_implementationOnly import SwiftSyntaxMacros
@_implementationOnly import SwiftSyntaxMacrosTestSupport
@_implementationOnly import XCTest

@testable import COWMacros

internal let testedMacros: [String : Macro.Type] = [
  "COW" : COWMacro.self,
  "COWIncluded" : COWIncludedMacro.self,
  "COWExcluded" : COWExcludedMacro.self,
  "COWStorage" : COWStorageMacro.self,
  "COWStorageAddProperty" : COWStorageAddPropertyMacro.self,
]

final class COWMacroTests: XCTestCase {
  
  func testCOWDoesNotAddsSubStructuresToEmptyStruct() {
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
  
  func testCOWAddsStorageTypeAndVarDeclToNoEmptyStruct() {
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
  
  func testCOWAddsStorageTypeAndCustomVarDeclToNoEmptyStruct() {
    assertMacroExpansion(
      """
      @COW(storageName: "_storage")
      struct Foo {
      
        var value: Int = 0
      
      }
      """,
      expandedSource:
      """
      
      struct Foo {
      
        var value: Int = 0 {
          get {
            return _storage.value
          }
          set {
            _storage.value = newValue
          }
        }
        struct __macro_local_7StoragefMu_: COW.CopyOnWriteStorage {
        
          var value: Int = 0
        }
        @COW._Box
        var _storage: __macro_local_7StoragefMu_ = __macro_local_7StoragefMu_()
      
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  
  func testCOWWithUserDefinedCOWStorage() {
    assertMacroExpansion(
      """
      @COW
      struct Bar: Equatable {
        
        @COWStorage
        struct Foo: Equatable {
          
          var bar: Int = 0
          
        }
        
        @COWExcluded
        var bar: Int {
          get {
            _$storage.bar
          }
          set {
            _$storage.bar = newValue
          }
        }
        
      }
      """,
      expandedSource:
      // FIXME: Bar.Foo conforms to COW.CopyOnWriteStorage in production environment
      """
      
      struct Bar: Equatable {
        struct Foo: Equatable {
          
          var bar: Int = 0
          
        }
        var bar: Int {
          get {
            _$storage.bar
          }
          set {
            _$storage.bar = newValue
          }
        }
        @COW._Box
        var _$storage: Foo = Foo()
      
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  // MARK: Diagnostics
  
  func testCOWDiagnosesInvalidTypeWithEnum() {
    assertMacroExpansion(
      """
      @COW
      enum Foo {
        case bar
      }
      """,
      expandedSource: """
      
      enum Foo {
        case bar
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@COW cannot be applied to enum type Foo", line: 1, column: 1)
      ],
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  func testCOWDiagnosesInvalidTypeWithClass() {
    assertMacroExpansion(
      """
      @COW
      class Foo {
      
        let value: Int = 0
      
      }
      """,
      expandedSource: """
      
      class Foo {
      
        let value: Int = 0
      
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@COW cannot be applied to class type Foo", line: 1, column: 1)
      ],
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  func testCOWDiagnosesInvalidTypeWithActor() {
    assertMacroExpansion(
      """
      @COW
      actor Foo {
      
        let value: Int = 0
      
      }
      """,
      expandedSource: """
      
      actor Foo {
      
        let value: Int = 0
      
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@COW cannot be applied to actor type Foo", line: 1, column: 1)
      ],
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
}
