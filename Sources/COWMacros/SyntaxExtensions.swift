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
  
  /// Checks if the initializer is a convenient initializer.
  ///
  internal var isConvenient: Bool {
    guard let body else {
      return false
    }
    // Recursively checks the contents in the body of the initializer. Once
    // a call to `self.init` has been found, the initializer then get confirmed
    // as a convenient initialzier.
    //
    // Swift's grammar ensures that the initializer can only be convenient or
    // designated. Developers cannot implement an initializer that conditionally
    // be both of them. Thus, once a `init`-forward has been found, the
    // initialzier can be confirmed as a convenient one.
    return body.doesContributeToConvenientInit
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

extension CodeBlockSyntax {
  
  internal var doesContributeToConvenientInit: Bool {
    if statements.doesContributeToConvenientInit {
      return true
    }
    return false
  }
  
}

extension CodeBlockItemListSyntax {
  
  internal var doesContributeToConvenientInit: Bool {
    for eachStmt in self {
      switch eachStmt.item {
      case .expr(let expr):
        if expr.doesContributeToConvenientInit {
          return true
        }
      case .stmt(let stmt):
        if stmt.doesContributeToConvenientInit {
          return true
        }
      case .decl(let decl):
        if decl.doesContributeToConvenientInit {
          return true
        }
      }
    }
    return false
  }
  
}

extension MemberBlockItemListSyntax {
  
  internal var doesContributeToConvenientInit: Bool {
    for eachItem in self {
      if eachItem.doesContributeToConvenientInit {
        return true
      }
    }
    return false
  }
  
}

extension MemberBlockItemSyntax {
  
  internal var doesContributeToConvenientInit: Bool {
    return decl.doesContributeToConvenientInit
  }
  
}

extension StmtSyntax {
  
  internal var doesContributeToConvenientInit: Bool {
    if let guardStmt = self.as(GuardStmtSyntax.self) {
      if guardStmt.body.doesContributeToConvenientInit {
        return true
      }
    }
    if let exprStmt = self.as(ExpressionStmtSyntax.self) {
      if exprStmt.expression.doesContributeToConvenientInit {
        return true
      }
    }
    return false
  }
  
}

extension ExprSyntax {
  
  internal var doesContributeToConvenientInit: Bool {
    if let callExpr = self.as(FunctionCallExprSyntax.self) {
      if callExpr.doesContributeToConvenientInit {
        return true
      }
    }
    
    if let ifExpr = self.as(IfExprSyntax.self) {
      if ifExpr.doesContributeToConvenientInit {
        return true
      }
    }
    
    if let switchExpr = self.as(SwitchExprSyntax.self) {
      if switchExpr.doesContributeToConvenientInit {
        return true
      }
    }
    
    return false
  }
}

extension DeclSyntax {
  
  internal var doesContributeToConvenientInit: Bool {
    if let ifConfigDecl = self.as(IfConfigDeclSyntax.self) {
      if ifConfigDecl.doesContributeToConvenientInit {
        return true
      }
    }
    
    return false
  }
}

extension FunctionCallExprSyntax {
  
  internal var doesContributeToConvenientInit: Bool {
    if let memberAccessExpr = calledExpression.as(MemberAccessExprSyntax.self),
       let selfExpr = memberAccessExpr.base?.as(DeclReferenceExprSyntax.self),
       selfExpr.baseName.tokenKind == .keyword(.`self`),
       memberAccessExpr.declName.baseName.tokenKind == .keyword(.`init`)
    {
      return true
    }
    return false
  }
  
}

extension IfExprSyntax {
  
  internal var doesContributeToConvenientInit: Bool {
    if body.doesContributeToConvenientInit {
      return true
    }
    switch elseBody {
    case .codeBlock(let codeBlock):
      if codeBlock.doesContributeToConvenientInit {
        return true
      }
    case .ifExpr(let ifExpr):
      if ifExpr.doesContributeToConvenientInit {
        return true
      }
    case .none:
      break;
    }
    return false
  }
  
}

extension IfConfigDeclSyntax {
  
  internal var doesContributeToConvenientInit: Bool {
    for eachClause in clauses {
      if eachClause.doesContributeToConvenientInit {
        return true
      }
    }
    return false
  }
  
}

extension IfConfigClauseSyntax {
  
  internal var doesContributeToConvenientInit: Bool {
    guard let elements else {
      return false
    }
    
    switch elements {
    case .attributes:
      break
    case .decls(let decls):
      if decls.doesContributeToConvenientInit {
        return true
      }
    case .statements(let stmts):
      if stmts.doesContributeToConvenientInit {
        return true
      }
    case .switchCases(let cases):
      if cases.doesContributeToConvenientInit {
        return true
      }
    case .postfixExpression(let expr):
      if expr.doesContributeToConvenientInit {
        return true
      }
      break
    }
    
    return false
  }
  
}

extension SwitchExprSyntax {
  
  internal var doesContributeToConvenientInit: Bool {
    if cases.doesContributeToConvenientInit {
      return true
    }
    return false
  }
  
}

extension SwitchCaseListSyntax {
  
  internal var doesContributeToConvenientInit: Bool {
    for eachCase in self {
      switch eachCase {
      case .ifConfigDecl:
        break
      case .switchCase(let switchCase):
        if switchCase.doesContributeToConvenientInit {
          return true
        }
      }
    }
    return false
  }
  
}

extension SwitchCaseSyntax {
  
  internal var doesContributeToConvenientInit: Bool {
    if statements.doesContributeToConvenientInit {
      return true
    }
    return false
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
