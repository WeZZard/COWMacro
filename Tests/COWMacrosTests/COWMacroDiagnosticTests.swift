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
  
  func testDiagnosesUndefinedBehaviorGivenOneVariableDeclMultipleBindings() {
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

      extension Storage: COW.CopyOnWriteStorage {
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message: "swift-syntax applies macros syntactically and there is no way to represent a variable declaration with multiple bindings that have accessors syntactically. While the compiler allows this expansion, swift-syntax cannot represent it and thus disallows it.",
          line: 8,
          column: 3
        ),
        DiagnosticSpec(
          message: "Decalring multiple stored properties over one variable declaration is an undefined behavior for the @COW macro.",
          line: 4,
          column: 3,
          fixIts: [
            FixItSpec(message: "Split the variable decalrations with multiple variable bindings into seperate decalrations.")
          ]
        ),
      ],
      macros: testedMacros
    )
  }
  
}
