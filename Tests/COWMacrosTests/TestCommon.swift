//
//  TestCommon.swift
//
//
//  Created by WeZZard on 7/7/23.
//

@_implementationOnly import SwiftBasicFormat
@_implementationOnly import SwiftDiagnostics
@_implementationOnly import SwiftParser
@_implementationOnly import SwiftSyntax
@_implementationOnly import SwiftSyntaxMacros
@_implementationOnly import SwiftSyntaxMacroExpansion
@_implementationOnly @testable import SwiftSyntaxMacrosTestSupport
@_implementationOnly import XCTest

@testable import COWMacros

internal let testedMacros: [String : Macro.Type] = [
  "COW" : COWMacro.self,
  "COWIncluded" : COWIncludedMacro.self,
  "COWExcluded" : COWExcludedMacro.self,
  "COWStorage" : COWStorageMacro.self,
  "COWStorageAddProperty" : COWStorageAddPropertyMacro.self,
  "COWMakeStorage" : COWMakeStorageMacro.self,
]

internal func assertMacroDiagnostics(
  _ originalSource: String,
  diagnostics: [DiagnosticSpec],
  macros: [String: Macro.Type],
  testModuleName: String = "TestModule",
  testFileName: String = "test.swift",
  indentationWidth: Trivia = .spaces(4),
  file: StaticString = #file,
  line: UInt = #line
) {
  // Parse the original source file.
  let origSourceFile = Parser.parse(source: originalSource)

  // Expand all macros in the source.
  let context = BasicMacroExpansionContext(
    sourceFiles: [origSourceFile: .init(moduleName: testModuleName, fullFilePath: testFileName)]
  )
  let _ = origSourceFile.expand(macros: macros, in: context).formatted(using: BasicFormat(indentationWidth: indentationWidth))
  
  if context.diagnostics.count != diagnostics.count {
    XCTFail(
      """
      Expected \(diagnostics.count) diagnostics but received \(context.diagnostics.count):
      \(context.diagnostics.map(\.debugDescription).joined(separator: "\n"))
      """,
      file: file,
      line: line
    )
  } else {
    for (actualDiag, expectedDiag) in zip(context.diagnostics, diagnostics) {
      assertDiagnostic(actualDiag, in: context, expected: expectedDiag)
    }
  }
}
