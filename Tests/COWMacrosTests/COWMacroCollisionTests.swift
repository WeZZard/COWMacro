//
//  COWMacroCollisionTests.swift
//
//
//  Created by WeZZard on 7/9/23.
//

@_implementationOnly import SwiftSyntaxMacros
@_implementationOnly import SwiftSyntaxMacrosTestSupport
@_implementationOnly import XCTest

@testable import COWMacros

/// Tests functionalities designed for preventing collisions.
///
final class COWMacroCollisionTests: XCTestCase {
  
  func testCustomStorageName() {
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
          _read {
            yield _storage.value
          }
          _modify {
            yield &_storage.value
          }
        }
      
        struct _$COWStorage: COW.CopyOnWriteStorage {
          var value: Int = 0
        }
        @COW._Box
        var _storage: _$COWStorage = _$COWStorage()
      
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
}
