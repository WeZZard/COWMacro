//
//  COWMacroUserStorageTests.swift
//
//
//  Created by WeZZard on 8/17/23.
//

@_implementationOnly import SwiftSyntaxMacros
@_implementationOnly import SwiftSyntaxMacrosTestSupport
@_implementationOnly import XCTest

@testable import COWMacros

final class COWMacroUserStorageTests: XCTestCase {
  
  func testUserStorage() {
    assertMacroExpansion(
      """
      @COW
      struct WithStorageType {
      
        @COWStorage
        struct Storage {
        
        }
        
        var value: Int
        
        init(value: Int) {
          self._$storage = Self._$makeStorage(value: value)
          self.value = value
        }
      }
      """, 
      expandedSource:
      """
      """,
      macros: testedMacros
    )
  }
  
}
