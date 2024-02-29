//
//  SyntaxExtensions.swift
//
//
//  Created by WeZZard on 7/1/23.
//

import SwiftSyntax

internal struct COWStoragePropertyDescriptor {
  
  enum DeclarePattern {
    
    case typeAndInitializer(TypeSyntax, ExprSyntax)
    
    case type(TypeSyntax)
    
    case initializer(ExprSyntax)
    
    init?(type: TypeSyntax?, initializer: ExprSyntax?) {
      switch (type, initializer) {
      case (let .some(type), let .some(initializer)):
        self = .typeAndInitializer(type, initializer)
      case (let .some(type), .none):
        self = .type(type)
      case (.none, let .some(initializer)):
        self = .initializer(initializer)
      case (.none, .none):
        return nil
      }
    }
    
  }
  
  internal let keyword: TokenSyntax
  
  internal let name: TokenSyntax
  
  internal let declarePattern: DeclarePattern
  
  internal var type: TypeSyntax? {
    switch declarePattern {
    case .typeAndInitializer(let typeSyntax, _):
      return typeSyntax
    case .type(let typeSyntax):
      return typeSyntax
    case .initializer:
      return nil
    }
  }
  
  internal var initializer: ExprSyntax? {
    switch declarePattern {
    case .typeAndInitializer(_, let exprSyntax):
      return exprSyntax
    case .type:
      return nil
    case .initializer(let exprSyntax):
      return exprSyntax
    }
  }
  
  internal func makeVarDecl() -> DeclSyntax {
    switch declarePattern {
    case .typeAndInitializer(let type, let initializer):
      return
        """
        \(keyword) \(name) : \(type) = \(initializer)
        """
    case .initializer(let initializer):
      return
        """
        \(keyword) \(name) = \(initializer)
        """
    case .type(let type):
      return
        """
        \(keyword) \(name) : \(type)
        """
    }
  }
  
}

extension WithAttributesSyntax {
  
  internal func hasMacroApplication(_ name: String) -> Bool {
    for each in attributes where each.hasName(name) {
      return true
    }
    return false
  }
  
}

extension StructDeclSyntax {
  
  internal var typeName: TokenSyntax {
    return TokenSyntax(
      name.tokenKind,
      presence: name.presence
    )
  }
  
  internal var copyOnWriteStorageName: TokenSyntax? {
    for eachAttribute in attributes {
      guard case .attribute(let attribute) = eachAttribute,
            let storageName = attribute.arguments?.storageName else {
        continue
      }
      return storageName
    }
    return nil
  }
  
  internal func isEquivalent(to other: StructDeclSyntax) -> Bool {
    return name == other.name
  }
  
}

extension FunctionDeclSyntax {
  
  internal var isStatic: Bool {
    for modifier in modifiers {
      for token in modifier.tokens(viewMode: .all) {
        if token.tokenKind == .keyword(.static) {
          return true
        }
      }
    }
    return true
  }
  
}

extension VariableDeclSyntax {
  
  internal var isVarBinding: Bool {
    return bindingSpecifier.tokenKind == .keyword(.var)
  }
  
  internal var isLetBinding: Bool {
    return bindingSpecifier.tokenKind == .keyword(.let)
  }
  
  internal var isIncluded: Bool {
    return hasMacroApplication(COWIncludedMacro.name)
  }
  
  internal var isExcluded: Bool {
    return hasMacroApplication(COWExcludedMacro.name)
  }
  
  internal var isNotExcludedAndStored: Bool {
    return !isExcluded && bindings.allSatisfy(\.isStored) && !isStatic
  }
  
  internal var isStatic: Bool {
    return modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) })
  }
  
  internal var hasSingleBinding: Bool {
    return bindings.count == 1
  }
  
  internal var singleBinding: PatternBindingSyntax? {
    if bindings.count == 1 {
      return bindings.first
    }
    return nil
  }
  
  internal var hasMultipleBindings: Bool {
    return bindings.count > 1
  }
  
  internal var storagePropertyDescriptors: [COWStoragePropertyDescriptor] {
    return bindings.compactMap { binding in
      binding.storagePropertyDescriptor(bindingSpecifier)
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
    return accessorBlock == nil
  }
  
  internal var isComputed: Bool {
    return accessorBlock != nil
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
          let declarePattern = COWStoragePropertyDescriptor.DeclarePattern(
            type: typeAnnotation?.type,
            initializer: initializer?.value
          ) else {
      return nil
    }
    
    return COWStoragePropertyDescriptor(
      keyword: keyword,
      name: identPattern.identifier,
      declarePattern: declarePattern
    )
  }
  
}

extension AttributeSyntax.Arguments {
  
  internal func getArg(at offset: Int, name: String) -> ExprSyntax? {
    guard case .argumentList(let args) = self else {
      return nil
    }
    
    guard offset < args.count else {
      return nil
    }
    
    let arg = args[args.index(args.startIndex, offsetBy: offset)]
    
    guard case .identifier(name) = arg.label?.tokenKind else {
      return nil
    }
    
    return arg.expression
  }
  
  internal func getArg(name: String) -> ExprSyntax? {
    guard case .argumentList(let args) = self else {
      return nil
    }
    
    let arg = args.first { arg in
      guard case .identifier(name) = arg.label?.tokenKind else {
        return false
      }
      
      return true
    }
    
    guard let arg = arg else {
      return nil
    }
    
    return arg.expression
  }
  
  /// The copy-on-write storage name
  internal var storageName: TokenSyntax? {
    guard let arg = getArg(name: "storageName") else {
      return nil
    }
    
    guard let storageName = arg.as(StringLiteralExprSyntax.self) else {
      return nil
    }
    
    return TokenSyntax(
      .identifier(storageName.trimmed.segments.description),
      presence: .present
    )
  }
  
  internal var storagePropertyDescriptor: COWStoragePropertyDescriptor? {
    guard let arg0 = getArg(name: "keyword"),
          let arg1 = getArg(name: "name") else {
      return nil
    }
    
    let keywordArg = arg0.as(MemberAccessExprSyntax.self)
    let nameArg = arg1.as(StringLiteralExprSyntax.self)
    
    guard let keyword = keywordArg?.declName.baseName else {
      return nil
    }
    guard let name = nameArg?.trimmed.segments.description else {
      return nil
    }
    
    let arg2 = getArg(name: "type")
    let arg3 = getArg(name: "initialValue")
    
    let typeArg = arg2?.as(StringLiteralExprSyntax.self)
    let initialValueArg = arg3?.as(StringLiteralExprSyntax.self)
    
    let type = typeArg?.trimmed.segments.description
    
    guard let declarePattern = COWStoragePropertyDescriptor.DeclarePattern(
      type: type.map(TypeSyntax.init),
      initializer: initialValueArg.map {
        ExprSyntax(stringLiteral: $0.trimmed.segments.description)
      }
    ) else {
      return nil
    }
    
    return COWStoragePropertyDescriptor(
      keyword: keyword,
      name: TokenSyntax(.stringSegment(name), presence: .present),
      declarePattern: declarePattern
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
    for parameter in signature.parameterClause.parameters {
      parameters.append(parameter.firstName.text + ":" + (parameter.type.genericSubstitution(genericParameterClause?.parameters) ?? "" ))
    }
    let returnType = signature.returnClause?.type.genericSubstitution(genericParameterClause?.parameters) ?? "Void"
    return SignatureStandin(parameters: parameters, returnType: returnType)
  }
  
  internal func isEquivalent(to other: InitializerDeclSyntax) -> Bool {
    return signatureStandin == other.signatureStandin
  }
  
}

private let autoSynthesizingProtocolTypes: Set<String> = [
  "Equatable",
  "Swift.Equatable",
  "Hashable",
  "Swift.Hashable",
  "Codable",
  "Swift.Codable",
  "Encodable",
  "Swift.Encodable",
  "Decodable",
  "Swift.Decodable",
]

extension DeclGroupSyntax {
  
  internal func collectAutoSynthesizingProtocolConformance() 
    -> [InheritedTypeSyntax]
  {
    guard let structDecl = self.as(StructDeclSyntax.self) else {
      return []
    }
    
    guard let inheritedTypes
            = structDecl.inheritanceClause?.inheritedTypes else {
      return []
    }
    
    return inheritedTypes.filter { each in
      if let ident = each.type.identifier {
        if autoSynthesizingProtocolTypes.contains(ident) {
          return true
        }
      }
      return false
    }
  }
  
  internal func collectExplicitInitializerDecls() -> [InitializerDeclSyntax] {
    return memberBlock.members.compactMap { eachItem in
      eachItem.decl.as(InitializerDeclSyntax.self)
    }
  }
  
  internal func collectUserDefinedStorageTypeDecls() -> [StructDeclSyntax] {
    return memberBlock.members.compactMap { eachItem in
      guard let structDecl = eachItem.decl.as(StructDeclSyntax.self),
            structDecl.hasMacroApplication(COWStorageMacro.name) else {
        return nil
      }
      return structDecl
    }
  }
  
  internal func collectAdoptableVarDecls() -> [VariableDeclSyntax] {
    return memberBlock.members.compactMap {
      eachItem -> VariableDeclSyntax? in
      guard let varDecl = eachItem.decl.as(VariableDeclSyntax.self),
            varDecl.isNotExcludedAndStored else {
        return nil
      }
      return varDecl.trimmed
    }
  }
  
  internal func collectStoredVarDecls() -> [VariableDeclSyntax] {
    return memberBlock.members.compactMap { eachItem in
      guard let varDecl = eachItem.decl.as(VariableDeclSyntax.self),
            varDecl.bindings.allSatisfy(\.isStored) else {
        return nil
      }
      return varDecl.trimmed
    }
  }
  
  internal var classifiedAdoptableVarDecls: (
    validWithInitializer: [VariableDeclSyntax],
    validWithTypeAnnoation: [VariableDeclSyntax],
    invalid: [VariableDeclSyntax]
  ) {
    let adoptableVarDecls = collectAdoptableVarDecls()
    
    let validVarDeclsAndBindings = adoptableVarDecls.map { varDecl in
      if let singleBinding = varDecl.singleBinding {
        return (varDecl: varDecl, singleBinding: singleBinding)
      } else {
        return nil
      }
    }.compactMap({$0})
    
    let hasInitializer = validVarDeclsAndBindings
      .filter(\.singleBinding.hasInitializer).map(\.varDecl)
    let hasTypeAnnoation = validVarDeclsAndBindings
      .filter(\.singleBinding.hasNoInitializer).map(\.varDecl)
    let invalid = adoptableVarDecls.filter(\.hasMultipleBindings)
    
    return (hasInitializer, hasTypeAnnoation, invalid)
  }
  
  internal func hasMemberStruct(equivalentTo other: StructDeclSyntax) -> Bool {
    for member in memberBlock.members {
      if let `struct` = member.as(MemberBlockItemSyntax.self)?.decl.as(StructDeclSyntax.self) {
        if `struct`.isEquivalent(to: other) {
          return true
        }
      }
    }
    return false
  }
  
  internal func hasMemberInit(equivalentTo other: InitializerDeclSyntax) -> Bool {
    for member in memberBlock.members {
      if let `init` = member.as(MemberBlockItemSyntax.self)?.decl.as(InitializerDeclSyntax.self) {
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

extension LabeledExprListSyntax {
  
  internal static func makeArgList(
    parameters: [FunctionParameterSyntax],
    usesTemplateArguments: Bool
  ) -> LabeledExprListSyntax {
    let parameterCount = parameters.count
    let args = parameters.enumerated().map {
      (index, eachParam) -> LabeledExprSyntax in
      
      let label = eachParam.firstName
      let name = eachParam.secondName ?? eachParam.firstName
      let nameToken: TokenSyntax
      if usesTemplateArguments {
        nameToken = TokenSyntax(.identifier("<#\(name.text)#>"), presence: .present)
      } else {
        nameToken = name
      }
      var syntax = LabeledExprSyntax(
        label: label.trimmed.text,
        expression: DeclReferenceExprSyntax(baseName: nameToken)
      ).with(\.colon, .colonToken(trailingTrivia: .spaces(1)))
      
      if parameterCount > 0 && (index + 1) < parameterCount {
        syntax = syntax
          .with(\.trailingComma, .commaToken(trailingTrivia: .spaces(1)))
      }
      
      return syntax
    }
    return LabeledExprListSyntax(args)
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
