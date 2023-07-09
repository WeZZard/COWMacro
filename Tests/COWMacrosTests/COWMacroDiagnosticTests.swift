//
//  COWMacroDiagnosticTests.swift
//
//
//  Created by WeZZard on 7/7/23.
//

@_implementationOnly import SwiftSyntaxMacros
@_implementationOnly import SwiftSyntaxMacrosTestSupport
@_implementationOnly import XCTest

@testable import COWMacros

final class COWMacroDiagnosticTests: XCTestCase {
  
  func testDiagnosesInvalidTypeWithEnum() {
    assertMacroDiagnostics(
      """
      @COW
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
  
  func testDiagnosesInvalidTypeWithClass() {
    assertMacroDiagnostics(
      """
      @COW
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
  
  func testDiagnosesInvalidTypeWithActor() {
    assertMacroDiagnostics(
      """
      @COW
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
  
  func testDiagnosesUndefinedBehaviorWithOneVariableDeclMultipleBindings() {
    assertMacroExpansion(
      """
      @COW
      struct Fee {
        
        @COWStorage
        struct Storage {
          
        }
        
        var foo: Int = 0, bar: Int = 0
        
      }
      """
      ,
      expandedSource:
      """
      
      struct Fee {
        struct Storage {
          
        }
        
        var foo: Int = 0, bar: Int = 0
        
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message: "Decalring multiple properties over one variable is an undefined behavior for the @COW macro.",
          line: 1,
          column: 1,
          fixIts: [
            FixItSpec(message: "Split the variable decalrations with multiple variable bindings into seperate decalrations.")
          ]
        ),
      ],
      macros: testedMacros
    )
  }
  
}
