//
//  COWMacroProtocolConformanceTests.swift
//
//
//  Created by jiangzhaoxuan on 2024/3/6.
//

@_implementationOnly import SwiftSyntaxMacros
@_implementationOnly import SwiftSyntaxMacrosTestSupport
@_implementationOnly import XCTest

@testable import COWMacros

/// Tests cases related to `Hashable`, `Equatable`, `Codable`, etc.
///
final class COWMacroProtocolConformanceTests: XCTestCase {
  
  /// Does not break the behavior of auto synthesizing protocols.
  ///
  /// `Hashable`, `Codeable` shall also work.
  ///
  /// The original struct:
  ///
  /// ```
  /// struct Foo: Equatable {
  ///
  ///   var value: Int = 0
  ///
  /// }
  /// ```
  ///
  func testStructWithPropertyAndConformsToAutoSynthesizingProtocols() {
    assertMacroExpansion(
      """
      @COW
      struct Foo: Equatable {
      
        var value: Int = 0
      
      }
      """,
      expandedSource:
      """
      
      struct Foo: Equatable {

        var value: Int = 0 {
          _read {
            yield _$storage.value
          }
          _modify {
            yield &_$storage.value
          }
        }

        struct _$COWStorage: COW.CopyOnWriteStorage, Equatable {
          var value: Int = 0
        }
        @COW._Box
        var _$storage: _$COWStorage = _$COWStorage()

      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  // FIXME: There is a compiler bug that breaks the build if the nested struct
  // does not conform to Equatable where the nesting struct does.
  // We have an integrated test case covering all the necessary workarounds:
  // see COWTest.testManuallyConformedEquatableStruct.
  // Remove the conditional compilation lines when the compiler bug is fixed.
  #if false
  /// Do not conform to `Equatable` if user explicitly declares `==`.
  ///
  /// The original struct:
  ///
  /// ```
  /// struct Foo: Equatable {
  ///
  ///   var value: Int = 0
  ///
  ///   static func == (lhs: Self, rhs: Self) -> Bool {
  ///     lhs.value == rhs.value
  ///   }
  ///
  /// }
  /// ```
  func testStructWithManualEquatableConformance() {
    assertMacroExpansion(
      """
      @COW
      struct Foo: Equatable {
      
        var value: Int = 0
        
        static func == (lhs: Self, rhs: Self) -> Bool {
          lhs.value == rhs.value
        }
      
      }
      """,
      expandedSource:
      """
      
      struct Foo: Equatable {

        var value: Int = 0 {
          _read {
            yield _$storage.value
          }
          _modify {
            yield &_$storage.value
          }
        }
        
        static func == (lhs: Self, rhs: Self) -> Bool {
          lhs.value == rhs.value
        }
      
        struct _$COWStorage: COW.CopyOnWriteStorage {
          var value: Int = 0
        }
        @COW._Box
        var _$storage: _$COWStorage = _$COWStorage()
      
      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  #endif
  
  /// Do not conform to `Hashable` if user explicitly declares `hash(into:)`.
  /// Conform to `Equatable` because `Hashable` implies such requirement.
  ///
  /// The original struct:
  ///
  /// ```
  /// struct Foo: Hashable {
  ///
  ///   var value: Int = 0
  ///
  ///   func hash(into hasher: inout Hasher) {
  ///     hasher.combine(value)
  ///   }
  ///
  /// }
  /// ```
  func testStructWithManualHashableConformance() {
    assertMacroExpansion(
      """
      @COW
      struct Foo: Hashable {
      
        var value: Int = 0
        
        func hash(into hasher: inout Hasher) {
          hasher.combine(value)
        }
      
      }
      """,
      expandedSource:
      """
      
      struct Foo: Hashable {

        var value: Int = 0 {
          _read {
            yield _$storage.value
          }
          _modify {
            yield &_$storage.value
          }
        }
        
        func hash(into hasher: inout Hasher) {
          hasher.combine(value)
        }

        struct _$COWStorage: COW.CopyOnWriteStorage, Swift.Equatable {
          var value: Int = 0
        }
        @COW._Box
        var _$storage: _$COWStorage = _$COWStorage()

      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  /// Do not conform to `Decodable` if user explicitly declares `init(from:)`.
  /// Conform to `Encodable` because `Codable` = `Decodable` + `Encodable`.
  ///
  /// The original struct:
  ///
  /// ```
  /// struct Foo: Codable {
  ///
  ///   var value: Int = 0
  ///
  ///   init(from decoder: Decoder) throws {
  ///     self.init(value: try decoder.singleValueContainer().decode(Int.self))
  ///   }
  ///
  /// }
  /// ```
  func testStructWithManualDecodableConformance() {
    assertMacroExpansion(
      """
      @COW
      struct Foo: Codable {
      
        var value: Int = 0
      
        init(from decoder: Decoder) throws {
          self.init(value: try decoder.singleValueContainer().decode(Int.self))
        }
      
      }
      """,
      expandedSource:
      """
      
      struct Foo: Codable {

        var value: Int = 0 {
          _read {
            yield _$storage.value
          }
          _modify {
            yield &_$storage.value
          }
        }

        init(from decoder: Decoder) throws {
          self.init(value: try decoder.singleValueContainer().decode(Int.self))
        }

        struct _$COWStorage: COW.CopyOnWriteStorage, Swift.Encodable {
          var value: Int = 0
        }
        @COW._Box
        var _$storage: _$COWStorage = _$COWStorage()

      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
  
  /// Do not conform to `Encodable` if user explicitly declares `encode(to:)`.
  /// Conform to `Decodable` because `Codable` = `Decodable` + `Encodable`.
  ///
  /// The original struct:
  ///
  /// ```
  /// struct Foo: Codable {
  ///
  ///   var value: Int = 0
  ///
  ///   func encode(to encoder: Encoder) throws {
  ///     let container = encoder.singleValueContainer()
  ///     try container.encode(value)
  ///   }
  ///
  /// }
  /// ```
  func testStructWithManualEncodableConformance() {
    assertMacroExpansion(
      """
      @COW
      struct Foo: Codable {
      
        var value: Int = 0
      
        func encode(to encoder: Encoder) throws {
          let container = encoder.singleValueContainer()
          try container.encode(value)
        }
      
      }
      """,
      expandedSource:
      """
      
      struct Foo: Codable {

        var value: Int = 0 {
          _read {
            yield _$storage.value
          }
          _modify {
            yield &_$storage.value
          }
        }

        func encode(to encoder: Encoder) throws {
          let container = encoder.singleValueContainer()
          try container.encode(value)
        }

        struct _$COWStorage: COW.CopyOnWriteStorage, Swift.Decodable {
          var value: Int = 0
        }
        @COW._Box
        var _$storage: _$COWStorage = _$COWStorage()

      }
      """,
      macros: testedMacros,
      indentationWidth: .spaces(2)
    )
  }
}
