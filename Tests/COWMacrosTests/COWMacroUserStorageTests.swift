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
          self._$storage = Storage(value: value)
          self.value = value
        }
      }
      """, 
      expandedSource:
      """
      struct WithStorageType {
        struct Storage {
            var value : Int
      
        }
      
        var value: Int {
            _read {
              yield _$storage.value
            }
            _modify {
              yield &_$storage.value
            }
        }
      
        init(value: Int) {
          self._$storage = Storage(value: value)
          self.value = value
        }
        @COW._Box
        var _$storage: Storage
      }
      """,
      macros: testedMacros
    )
  }
  
}
