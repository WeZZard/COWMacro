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
  
  func testCOWAddsStorageTypeMemberAndMakeUniqueStorageFunctionToNoEmptyStruct() {
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
        struct Storage: COW.CopyOnWriteStorage {
        
          var value: Int = 0
        }
        @COW._Box
        var _$storage: Storage = Storage()
      
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
