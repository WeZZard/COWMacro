//
//  COWStorageMacroTests.swift
//
//
//  Created by WeZZard on 7/1/23.
//

@_implementationOnly import SwiftSyntaxMacros
@_implementationOnly import SwiftSyntaxMacrosTestSupport
@_implementationOnly import XCTest

@testable import COWMacros

final class COWStorageMacroTests: XCTestCase {
  
  func testCOWStorageAddsConformanceToCopyOnWritableSotrageOnStruct() {
    assertMacroExpansion(
      """
      @COWStorage
      struct Foo {
      }
      """,
      expandedSource: """
      
      struct Foo {
      }
      """,
      macros: testedMacros
    )
  }
  
  func testCOWStorageAddsNothingOnEnum() {
    assertMacroExpansion(
      """
      @COWStorage
      enum Foo {
      }
      """,
      expandedSource: """
      
      enum Foo {
      }
      """,
      macros: testedMacros
    )
  }
  
  func testCOWStorageAddsNothingOnClass() {
    assertMacroExpansion(
      """
      @COWStorage
      class Foo {
      }
      """,
      expandedSource: """
      
      class Foo {
      }
      """,
      macros: testedMacros
    )
  }
  
}
