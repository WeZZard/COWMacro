//
//  COWMacroExplicitInitTests.swift
//
//
//  Created by WeZZard on 7/9/23.
//

@_implementationOnly import SwiftSyntaxMacros
@_implementationOnly import SwiftSyntaxMacrosTestSupport
@_implementationOnly import XCTest

@testable import COWMacros

final class COWMacroExplicitInitTests: XCTestCase {
  
  /// (
  ///   struct
  ///     explicit initializers
  /// )
  ///
  /// When struct has explicit initializers and has no custom storage, the
  /// macro should be expanded to:
  ///   - Create `struct StorageType: CopyOnWriteStorage` as the subtype of
  ///     the applied struct and generates an explicit memberwise
  ///     initializer.
  ///   - Create `var _$storage: StorageType` in the applied struc
  ///     **without** initializer.
  ///   - Forward properties in the applied struct to the peered properties
  ///     in the copy-on-write storage
  ///   - Create a static make storage method in the applied struct.
  ///   - Diasnose an error that the explicit initializers in the applied
  ///     struct should call the static make storage method before
  ///     initializing properties.
  ///
  /// The original struct:
  ///
  /// ```
  /// struct Foo {
  ///
  ///   var value: Int
  ///
  ///   init(value: Int) {
  ///     self.value = value
  ///   }
  ///
  /// }
  /// ```
  ///
  func testExplicitInits() {
    assertMacroExpansion(
      """
      @COW
      struct Foo {
      
        var value: Int
      
        init(value: Int) {
          self.value = value
        }
      }
      """,
      expandedSource:
      """
      
      struct Foo {
        
        var value: Int {
          get {
            return _$storage.value
          }
          set {
            _$storage.value = newValue
          }
        }
        
        struct __macro_local_7StoragefMu_: COW.CopyOnWriteStorage {
        
          var value: Int
      
          init(value: Int) {
            self.value = value
          }
      
        }
        
        @COW._Box
        var _$storage: __macro_local_7StoragefMu_
        
        static func _$makeStorage(value: Int) -> __macro_local_7StoragefMu_ {
          return __macro_local_7StoragefMu_(value: value)
        }
      
        init(value: Int) {
          self.value = value
        }
      
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@COW macro requires you to insert `self._$storage = Self._$makeStorage(value: <#value#>)` before initializing the properties to make the code compilable.", line: 6, column: 3),
      ],
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  /// (
  ///   struct
  ///     explicit initializers
  ///   custom storage
  ///     one explicit initializer
  /// )
  ///
  /// When struct has explicit initializers and has custom storage with one
  /// explicit initializer, the macro should be expanded to:
  ///   - Create `var _$storage: StorageType` in the applied struc
  ///     **without** initializer.
  ///   - Forwards properties in the applied struct to the peered properties
  ///     in the copy-on-write storage
  ///   - Creates a static make storage method in the applied struct and
  ///     forwards to the explicit initiaizer of the custom storage.
  ///   - Diasnoses an error that the explicit initializers in the applied
  ///     struct should call the static make storage method before
  ///     initializing properties.
  ///
  /// The original struct:
  ///
  /// ```
  /// struct Foo {
  ///
  ///   var value: Int
  ///
  ///   init(value: Int) {
  ///     self.value = value
  ///   }
  ///
  /// }
  /// ```
  ///
  func testExplicitInits_CustomStorage_ExplicitInit() {
    assertMacroExpansion(
      """
      @COW
      struct Foo {
      
        @COWStorage
        struct Bar {
      
          var value: Int
      
          init(value: Int) {
            self.value = value
          }
      
        }
      
        init(value: Int) {
          self.value = value
        }
      }
      """,
      expandedSource:
      """
      @COW
      struct Foo {
      
        struct Bar: CopyOnWriteStorage {
      
          var value: Int
      
          init(value: Int) {
            self.value = value
          }
      
        }
      
        @COW._Box
        var _$storage: Bar
        
        static func _$makeStorage(value: Int) -> Bar {
          return Bar(value: value)
        }
      
        init(value: Int) {
          self.value = value
        }
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  
  /// (
  ///   struct
  ///     explicit initializers
  ///   custom storage
  ///     multiple explicit initializers
  /// )
  ///
  /// When struct has explicit initializers and has custom storage with one
  /// explicit initializer, the macro should be expanded to:
  ///   - Create `var _$storage: StorageType` in the applied struc
  ///     **without** initializer.
  ///   - Forwards properties in the applied struct to the peered properties
  ///     in the copy-on-write storage
  ///   - Diasnoses an error that the static make storage method could not
  ///     be generated since there are multiple explicit inits exist for the
  ///     copy-on-write storage type.
  ///   - Diasnoses an error that the explicit initializers in the applied
  ///     struct should call the static make storage method before
  ///     initializing properties.
  ///
  /// The original struct:
  ///
  /// ```
  /// struct Foo {
  ///
  ///   var value: Int
  ///
  ///   init(value: Int) {
  ///     self.value = value
  ///   }
  ///
  /// }
  /// ```
  ///
  func testExplicitInits_CustomStorage_ExplicitInits() {
    
  }
  
  /// (
  ///   struct
  ///     explicit initializers
  ///     static make storage method
  ///   custom storage
  ///     one explicit initializer
  /// )
  ///
  /// When struct has explicit initializers and has custom storage with one
  /// explicit initializer, the macro should be expanded to:
  ///   - Create `var _$storage: StorageType` in the applied struc
  ///     **without** initializer.
  ///   - Forwards properties in the applied struct to the peered properties
  ///     in the copy-on-write storage
  ///   - Diasnoses an error that the explicit initializers in the applied
  ///     struct should call the static make storage method before
  ///     initializing properties.
  ///
  func testExplicitInits_StaticMakeStorageMethod_CustomStorage_ExplicitInit() {
    
  }
  
  /// (
  ///   struct
  ///     explicit initializers
  ///     static make storage method
  ///   custom storage
  ///     one explicit initializer
  /// )
  ///
  /// When struct has explicit initializers and has custom storage with
  /// multiple explicit initializer, the macro should be expanded to:
  ///   - Create `var _$storage: StorageType` in the applied struc
  ///     **without** initializer.
  ///   - Forwards properties in the applied struct to the peered properties
  ///     in the copy-on-write storage
  ///   - Diasnoses an error that the explicit initializers in the applied
  ///     struct should call the static make storage method before
  ///     initializing properties.
  ///
  func testExplicitInits_StaticMakeStorageMethod_CustomStorage_ExplicitInits() {
    
  }
  
}
