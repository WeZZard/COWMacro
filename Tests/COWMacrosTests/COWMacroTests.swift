@_implementationOnly import SwiftSyntaxMacros
@_implementationOnly import SwiftSyntaxMacrosTestSupport
@_implementationOnly import XCTest

@testable import COWMacros

final class COWMacroTests: XCTestCase {
  
  func testCOWDoesNotAddsSubStructuresToEmptyStruct() {
    assertMacroExpansion(
      """
      @COW
      struct Foo {
      }
      """,
      expandedSource: """
      
      struct Foo {
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  func testCOWAddsStorageTypeAndVarDeclToNoEmptyStruct() {
    assertMacroExpansion(
      """
      @COW
      struct Foo {
      
        var value: Int = 0
      
      }
      """,
      expandedSource:
      """
      
      struct Foo {
      
        var value: Int = 0 {
          get {
            return _$storage.value
          }
          set {
            _$storage.value = newValue
          }
        }
        struct __macro_local_7StoragefMu_: COW.CopyOnWriteStorage {
        
          var value: Int = 0
        }
        @COW._Box
        var _$storage: __macro_local_7StoragefMu_ = __macro_local_7StoragefMu_()
      
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  func testCOWAddsStorageTypeAndCustomVarDeclToNoEmptyStruct() {
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
          get {
            return _storage.value
          }
          set {
            _storage.value = newValue
          }
        }
        struct __macro_local_7StoragefMu_: COW.CopyOnWriteStorage {
        
          var value: Int = 0
        }
        @COW._Box
        var _storage: __macro_local_7StoragefMu_ = __macro_local_7StoragefMu_()
      
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  
  func testCOWWithUserDefinedCOWStorage() {
    assertMacroExpansion(
      """
      @COW
      struct Bar: Equatable {
        
        @COWStorage
        struct Foo: Equatable {
          
          var bar: Int = 0
          
        }
        
        @COWExcluded
        var bar: Int {
          get {
            _$storage.bar
          }
          set {
            _$storage.bar = newValue
          }
        }
        
      }
      """,
      expandedSource:
      // FIXME: Bar.Foo conforms to COW.CopyOnWriteStorage in production environment
      """
      
      struct Bar: Equatable {
        struct Foo: Equatable {
          
          var bar: Int = 0
          
        }
        var bar: Int {
          get {
            _$storage.bar
          }
          set {
            _$storage.bar = newValue
          }
        }
        @COW._Box
        var _$storage: Foo = Foo()
      
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  // MARK: Diagnostics
  
  
}
