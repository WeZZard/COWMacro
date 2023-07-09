//
//  SyntaxExtensions.swift
//
//
//  Created by WeZZard on 7/1/23.
//

import SwiftSyntax

internal struct COWStoragePropertyDescriptor {
  
  internal let keyword: TokenSyntax
  
  internal let name: TokenSyntax
  
  internal let type: TypeSyntax?
  
  internal let initializer: ExprSyntax
  
  internal func makeVarDecl() -> DeclSyntax {
    if let typeAnnotation = type {
      return
        """
        \(keyword) \(name) : \(typeAnnotation) = \(initializer)
        """
    } else {
      return
        """
        \(keyword) \(name) = \(initializer)
        """
    }
  }
  
}

extension WithAttributesSyntax {
  
  internal func hasMacroApplication(_ name: String) -> Bool {
    guard let attributes else {
      return false
    }
    for each in attributes where each.hasName(name) {
      return true
    }
    return false
  }
  
}

extension StructDeclSyntax {
  
  internal var typeName: TokenSyntax {
    return TokenSyntax(
     identifier.tokenKind,
      presence: identifier.presence
    )
  }
  
  internal var copyOnWriteStorageName: TokenSyntax? {
    guard let attributes else {
      return nil
    }
    
    for eachAttribute in attributes {
      guard case .attribute(let attribute) = eachAttribute,
            let storageName = attribute.argument?.storageName else {
        continue
      }
      return storageName
    }
    return nil
  }
  
  internal func isEquivalent(to other: StructDeclSyntax) -> Bool {
    return identifier == other.identifier
  }
  
}

extension FunctionDeclSyntax {
  
  internal var isStatic: Bool {
    if let modifiers {
      for modifier in modifiers {
        for token in modifier.tokens(viewMode: .all) {
          if token.tokenKind == .keyword(.static) {
            return true
          }
        }
      }
    }
    return true
  }
  
}

extension VariableDeclSyntax {
  
  internal var isIncluded: Bool {
    hasMacroApplication(COWIncludedMacro.name)
  }
  
  internal var isExcluded: Bool {
    hasMacroApplication(COWExcludedMacro.name)
  }
  
  internal var isIncludeable: Bool {
    return !isExcluded
  }
  
  internal var hasSingleBinding: Bool {
    return bindings.count == 1
  }
  
  internal var hasMultipleBindings: Bool {
    return bindings.count > 1
  }
  
  internal var storagePropertyDescriptors: [COWStoragePropertyDescriptor] {
    bindings.compactMap { binding in
      binding.storagePropertyDescriptor(bindingKeyword)
    }
  }
  
}

extension AttributeListSyntax.Element {
  
  /// Attribute list may contains a `#if ... #else ... #end` wrapped
  /// attributes. Unconditional attribute name means attributes outside
  /// `#if ... #else ... #end`.
  ///
  internal func hasName(_ name: String) -> Bool {
    switch self {
    case .attribute(let syntax):
      return syntax.hasName(name)
    case .ifConfigDecl:
      return false
    }
  }
  
}


extension AttributeSyntax {
  
  internal func hasName(_ name: String) -> Bool {
    return attributeName.tokens(viewMode: .all).map({ $0.tokenKind }) == [.identifier(name)]
  }
  
}

extension PatternBindingSyntax {
  
  internal var isStored: Bool {
    return accessor == nil
  }
  
  internal var isComputed: Bool {
    return accessor != nil
  }
  
  internal var hasInitializer: Bool {
    return initializer != nil
  }
  
  internal var hasNoInitializer: Bool {
    return initializer == nil
  }
  
  internal func storagePropertyDescriptor(
    _ keyword: TokenSyntax
  ) -> COWStoragePropertyDescriptor? {
    guard let identPattern = pattern.as(IdentifierPatternSyntax.self),
          let initializer = initializer else {
      return nil
    }
    
    return COWStoragePropertyDescriptor(
      keyword: keyword,
      name: identPattern.identifier,
      type: typeAnnotation?.type,
      initializer: initializer.value
    )
  }
  
}

extension AttributeSyntax.Argument {
  
  /// The copy-on-write storage name
  internal var storageName: TokenSyntax? {
    guard case .argumentList(let args) = self else {
      return nil
    }
    
    guard args.count >= 1 else {
      return nil
    }
    
    let arg0 = args[args.startIndex]
    
    guard case .identifier("storageName") = arg0.label?.tokenKind else {
      return nil
    }
    
    guard let storageNameArg
            = arg0.expression.as(StringLiteralExprSyntax.self) else {
      return nil
    }
    
    return TokenSyntax(
      .identifier(storageNameArg.trimmed.segments.description),
      presence: .present
    )
  }
  
  internal var storagePropertyDescriptor: COWStoragePropertyDescriptor? {
    guard case .argumentList(let args) = self else {
      return nil
    }
    
    guard args.count >= 4 else {
      return nil
    }
    
    let arg0 = args[args.startIndex]
    let arg1 = args[args.index(args.startIndex, offsetBy: 1)]
    let arg2 = args[args.index(args.startIndex, offsetBy: 2)]
    let arg3 = args[args.index(args.startIndex, offsetBy: 3)]
    
    guard case .identifier("keyword") = arg0.label?.tokenKind,
          case .identifier("name") = arg1.label?.tokenKind,
          case .identifier("type") = arg2.label?.tokenKind,
          case .identifier("initialValue") = arg3.label?.tokenKind else {
      return nil
    }
    
    let keywordArg = arg0.expression.as(MemberAccessExprSyntax.self)
    let nameArg = arg1.expression.as(StringLiteralExprSyntax.self)
    let typeArg = arg2.expression.as(StringLiteralExprSyntax.self)
    let initialValueArg = arg3.expression.as(StringLiteralExprSyntax.self)
    
    guard let keyword = keywordArg?.name else {
      return nil
    }
    guard let name = nameArg?.trimmed.segments.description else {
      return nil
    }
    let type = typeArg?.trimmed.segments.description
    guard let initialValue = initialValueArg?.trimmed.segments.description else {
      return nil
    }
    
    return COWStoragePropertyDescriptor(
      keyword: keyword,
      name: TokenSyntax(.stringSegment(name), presence: .present),
      type: type.map(TypeSyntax.init),
      initializer: ExprSyntax(stringLiteral: initialValue)
    )
  }
  
}

extension InitializerDeclSyntax {
  
  internal struct SignatureStandin: Equatable {
    var parameters: [String]
    var returnType: String
  }
  
  internal var signatureStandin: SignatureStandin {
    var parameters = [String]()
    for parameter in signature.input.parameterList {
      parameters.append(parameter.firstName.text + ":" + (parameter.type.genericSubstitution(genericParameterClause?.genericParameterList) ?? "" ))
    }
    let returnType = signature.output?.returnType.genericSubstitution(genericParameterClause?.genericParameterList) ?? "Void"
    return SignatureStandin(parameters: parameters, returnType: returnType)
  }
  
  internal func isEquivalent(to other: InitializerDeclSyntax) -> Bool {
    return signatureStandin == other.signatureStandin
  }
  
}

extension DeclGroupSyntax {
  
  internal func hasMemberStruct(equivalentTo other: StructDeclSyntax) -> Bool {
    for member in memberBlock.members {
      if let `struct` = member.as(MemberDeclListItemSyntax.self)?.decl.as(StructDeclSyntax.self) {
        if `struct`.isEquivalent(to: other) {
          return true
        }
      }
    }
    return false
  }
  
  internal func hasMemberInit(equivalentTo other: InitializerDeclSyntax) -> Bool {
    for member in memberBlock.members {
      if let `init` = member.as(MemberDeclListItemSyntax.self)?.decl.as(InitializerDeclSyntax.self) {
        if `init`.isEquivalent(to: other) {
          return true
        }
      }
    }
    return false
  }
  
  internal var isStruct: Bool {
    return self.is(StructDeclSyntax.self)
  }
  
  internal func addIfNeeded<Declaration: DeclSyntaxProtocol>(
    _ decl: Declaration?,
    to declarations: inout [DeclSyntax]
  ) {
    addIfNeeded(DeclSyntax(decl), to: &declarations)
  }
  
}

extension Sequence {
  
  internal func anySatisfies(_ keyPath: KeyPath<Element, Bool>) -> Bool {
    for each in self where each[keyPath: keyPath] {
      return true
    }
    return false
  }
  
  internal func allSatisfy(_ keyPath: KeyPath<Element, Bool>) -> Bool {
    return allSatisfy { element in
      element[keyPath: keyPath]
    }
  }
  
}
