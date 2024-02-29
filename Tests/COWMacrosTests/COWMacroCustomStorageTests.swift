//
//  COWMacroCustomStorageTests.swift
//
//
//  Created by WeZZard on 7/9/23.
//

@_implementationOnly import SwiftSyntaxMacros
@_implementationOnly import SwiftSyntaxMacrosTestSupport
@_implementationOnly import XCTest

@testable import COWMacros

final class COWMacroCustomStorageTests: XCTestCase {
  
  /// Developers can manually offer a copy-on-write storage and make
  /// protocols
  ///
  /// The original struct:
  ///
  /// ```
  /// struct Foo: Equatable {
  ///
  ///   var value: String
  ///
  /// }
  /// ```
  ///
  func testStruct_ProtocolConformance_CustomCOWStorage() {
    assertMacroExpansion(
      """
      @COW
      struct Foo: Equatable {
        
        @COWStorage
        struct Bar: Equatable {
          
          var value: String
          
        }
        
        var value: String {
          get {
            return _$storage.value
          }
          set {
            _$storage.value = newValue
          }
        }
        
      }
      """,
      expandedSource:
      """
      
      struct Foo: Equatable {
        
        struct Bar: Equatable {
          
          var value: String
          
        }
        
        var value: String {
          get {
            return _$storage.value
          }
          set {
            _$storage.value = newValue
          }
        }
        @COW._Box
        var _$storage: Bar

        init(value: String) {
          self._$storage = Bar(value: value)
        }
        
      }

      extension Bar: COW.CopyOnWriteStorage {
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
}
