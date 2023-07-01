@_implementationOnly import SwiftSyntaxMacros
@_implementationOnly import SwiftSyntaxMacrosTestSupport
@_implementationOnly import XCTest

@testable import COWMacros

private let testedMacros: [String : Macro.Type] = [
  "COW" : COWMacro.self,
  "COWIncluded" : COWIncludedMacro.self,
  "COWExcluded" : COWExcludedMacro.self,
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
            return _$storage.withUnsafeMutablePointerToElements { elem in
              elem.pointee.value
            }
          }
          set {
            _makeUniqueStorageIfNeeded()
            _$storage.withUnsafeMutablePointerToElements { elem in
              elem.pointee.value = newValue
            }
          }
        }
        struct Storage {
        
          var value: Int = 0
        }
        var _$storage = ManagedBuffer<Void, Storage> .create(minimumCapacity: 1) { prototype in
          prototype.withUnsafeMutablePointerToHeader {
            $0.pointee = Void()
          }
          prototype.withUnsafeMutablePointerToElements { storage in
            storage.pointee = Storage()
          }
        }
        internal nonisolated mutating func _makeUniqueStorageIfNeeded() {
          guard !isKnownUniquelyReferenced(&_$storage) else {
            return
          }
          _$storage = .create(minimumCapacity: 1) { prototype in
            prototype.withUnsafeMutablePointerToHeader {
              $0.pointee = Void()
            }
            prototype.withUnsafeMutablePointerToElements { elements in
              _$storage.withUnsafeMutablePointerToElements { oldElements in
                elements.pointee = oldElements.pointee
              }
            }
          }
        }
      
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
