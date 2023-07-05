//
//  Diagnostic.swift
//
//
//  Created by WeZZard on 7/1/23.
//

@_implementationOnly import SwiftDiagnostics

import SwiftSyntax

internal struct COWDiagnostic: DiagnosticMessage {
  
  internal enum ID: String {
    case invalidType = "invalid type"
    case missingInitializer = "missing initializer"
    case duplicateCOWStorages = "duplciate COW storages"
    case requiresCOWStorage = "requires COW storage"
    case requiresManuallyInitializeStorage = "requires manually initialize storage"
    case internalInconsistency = "internal inconsistency"
  }
  
  internal var message: String
  
  internal var diagnosticID: MessageID
  
  internal var severity: DiagnosticSeverity
  
  internal init(
    message: String,
    diagnosticID: MessageID,
    severity: DiagnosticSeverity = .error
  ) {
    self.message = message
    self.diagnosticID = diagnosticID
    self.severity = severity
  }
  
  internal init(
    message: String,
    domain: String,
    id: ID,
    severity: DiagnosticSeverity = .error
  ) {
    self.message = message
    self.diagnosticID = MessageID(domain: domain, id: id.rawValue)
    self.severity = severity
  }
  
}

extension DiagnosticsError {
  
  internal init<S: SyntaxProtocol>(
    syntax: S,
    message: String,
    domain: String = "COW",
    id: COWDiagnostic.ID,
    severity: DiagnosticSeverity = .error
  ) {
    self.init(diagnostics: [
      Diagnostic(
        node: Syntax(syntax),
        message: COWDiagnostic(
          message: message,
          domain: domain,
          id: id,
          severity: severity
        )
      )
    ])
  }
  
}
