//
//  COWMacroPropertyWrapperTests.swift
//
//
//  Created by WeZZard on 7/9/23.
//

@_implementationOnly import SwiftSyntaxMacros
@_implementationOnly import SwiftSyntaxMacrosTestSupport
@_implementationOnly import XCTest

@testable import COWMacros

/// Test cases in the following class assumes there is such a property
/// wrapper type:
///
/// ```
/// @propertyWrapper
/// struct Capitalized<Wrapped: StringProtocol> {
///
///   var wrappedValue: Wrapped {
///     didSet {
///       self.wrappedValue = wrappedValue.capitalized
///     }
///   }
///
/// }
/// ```
///
final class COWMacroPropertyWrapperTests: XCTestCase {
  
  /// The original struct:
  ///
  /// ```
  /// struct Bar {
  ///
  ///   @Capitalized
  ///   var value: String
  ///
  /// }
  /// ```
  ///
  func testStruct_CustomCOWStorage_PropertyWrapper() {
    assertMacroExpansion(
      """
      @COW
      struct Bar {
        
        @COWStorage
        struct Storage {
          
          @Capitalized
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
      
      struct Bar {
        
        struct Storage {
          
          @Capitalized
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
        var _$storage: Storage

        init(value: String) {
          self._$storage = Storage(value: value)
        }
        
      }

      extension Storage: COW.CopyOnWriteStorage {
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  /// In this case, developers may want to precisely control the
  /// initialization process of some proeprties.
  ///
  /// The original struct
  ///
  /// ```
  /// struct Foo {
  ///
  ///   @Capitalized
  ///   var value: String
  ///
  ///   init(value: Capitalized<String>) {
  ///     self._value = value
  ///   }
  ///
  /// }
  /// ```
  ///
  func testStruct_ExplicitInit_CustomCOWStorage_PropertyWrapper() {
    // TODO: Diagnose when the Foo.init is not adjusted for the macro
    assertMacroExpansion(
      """
      @COW
      struct Foo {
        
        @COWStorage
        struct Storage {
          
          @Capitalized
          var value: String
      
          init(value: Capitalized<String>) {
            _value = value
          }
          
        }
        
        var value: String {
          get {
            return _$storage.value
          }
          set {
            _$storage.value = newValue
          }
        }
      
        init(value: Capitalized<String>) {
          self._$storage = Storage(value: value)
        }
        
      }
      """,
      expandedSource:
      """
      
      struct Foo {
        
        struct Storage {
          
          @Capitalized
          var value: String

          init(value: Capitalized<String>) {
            _value = value
          }
          
        }
        
        var value: String {
          get {
            return _$storage.value
          }
          set {
            _$storage.value = newValue
          }
        }

        init(value: Capitalized<String>) {
          self._$storage = Storage(value: value)
        }
        @COW._Box
        var _$storage: Storage
        
      }

      extension Storage: COW.CopyOnWriteStorage {
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
}
