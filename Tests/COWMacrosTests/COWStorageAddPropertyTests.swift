//
//  COWStorageAddPropertyTests.swift
//
//
//  Created by WeZZard on 7/2/23.
//

@_implementationOnly import SwiftSyntaxMacros
@_implementationOnly import SwiftSyntaxMacrosTestSupport
@_implementationOnly import XCTest

@testable import COWMacros

final class COWStorageAddPropertyTests: XCTestCase {
  
  func testCOWStorageAddPropertyCanAddPropertyToCOWStorage() {
    assertMacroExpansion(
      """
      @COWStorage
      @COWStorageAddProperty(
        keyword: .var,
        name: "value",
        type: "Int",
        initialValue: "0"
      )
      struct Foo {
      }
      """,
      expandedSource: """
      
      struct Foo {
        var value : Int = 0
      }
      extension Foo: COW.CopyOnWriteStorage {
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  func testCOWStorageAddPropertyCanAddPropertyToCOWStorageWithoutType() {
    assertMacroExpansion(
      """
      @COWStorage
      @COWStorageAddProperty(
        keyword: .var,
        name: "value",
        type: nil,
        initialValue: "0"
      )
      struct Foo {
      }
      """,
      expandedSource: """
      
      struct Foo {
        var value = 0
      }
      extension Foo: COW.CopyOnWriteStorage {
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
}
