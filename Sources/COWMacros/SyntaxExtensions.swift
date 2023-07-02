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

extension StructDeclSyntax {
  
  internal func hasMacroApplication(_ name: String) -> Bool {
    guard let attributes else {
      return false
    }
    for each in attributes where each.hasName(name) {
      return true
    }
    return false
  }
  
  internal var copyOnWriteStorageName: TokenSyntax? {
    guard case .attribute(let attribute) = attributes?.first else {
      return nil
    }
    return attribute.argument?.storageName
  }
  
  internal func isEquivalent(to other: StructDeclSyntax) -> Bool {
    return identifier == other.identifier
  }
  
}

extension VariableDeclSyntax {
  
  internal struct Info {
    
    internal let hasStorage: Bool
    
    internal let isMarkedIncluded: Bool
    
    internal let isMarkedExcluded: Bool
    
    internal let hasDefaultValue: Bool
    
  }
  
  internal var info: Info? {
    guard let binding = bindings.first else {
      return nil
    }
    
    let hasStorage = binding.accessor == nil
    let hasDefaultValue = binding.initializer != nil
    let isMarkedIncluded = hasMacroApplication(COWIncludedMacro.name)
    let isMarkedExcluded = hasMacroApplication(COWExcludedMacro.name)
    
    return Info(
      hasStorage: hasStorage,
      isMarkedIncluded: isMarkedIncluded,
      isMarkedExcluded: isMarkedExcluded,
      hasDefaultValue: hasDefaultValue
    )
  }
  
  internal var storagePropertyDescritors: [COWStoragePropertyDescriptor] {
    bindings.compactMap { binding in
      binding.storagePropertyDescritor(bindingKeyword)
    }
  }
  
  internal var isIncludeable: Bool {
    guard let info = info else {
      return false
    }
    return !info.isMarkedExcluded
  }
  
  internal var identifierPattern: IdentifierPatternSyntax? {
    bindings.first?.pattern.as(IdentifierPatternSyntax.self)
  }
  
  internal var identifier: TokenSyntax? {
    identifierPattern?.identifier
  }
  
  internal func hasMacroApplication(_ name: String) -> Bool {
    guard let attributes else {
      return false
    }
    for each in attributes where each.hasName(name) {
      return true
    }
    return false
  }
  
  internal func firstMacroApplication(_ name: String) -> AttributeSyntax? {
    guard let attributes else {
      return nil
    }
    for each in attributes where each.hasName(name) {
      switch each {
      case .attribute(let attrSyntax):
        return attrSyntax
      case .ifConfigDecl:
        break
      }
    }
    return nil
  }
  
  internal var isInstance: Bool {
    if let modifiers {
      for modifier in modifiers {
        for token in modifier.tokens(viewMode: .all) {
          if token.tokenKind == .keyword(.static) || token.tokenKind == .keyword(.class) {
            return false
          }
        }
      }
    }
    return true
  }
  
  internal func isEquivalent(to other: VariableDeclSyntax) -> Bool {
    if isInstance != other.isInstance {
      return false
    }
    return identifier?.text == other.identifier?.text
  }
  
}

extension PatternBindingSyntax {
  
  internal func storagePropertyDescritor(_ keyword: TokenSyntax) -> COWStoragePropertyDescriptor? {
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

extension TypeSyntax {
  
  internal func genericSubstitution(_ parameters: GenericParameterListSyntax?) -> String? {
    var genericParameters = [String : TypeSyntax?]()
    if let parameters {
      for parameter in parameters {
        genericParameters[parameter.name.text] = parameter.inheritedType
      }
    }
    var iterator = self.asProtocol(TypeSyntaxProtocol.self).tokens(viewMode: .sourceAccurate).makeIterator()
    guard let base = iterator.next() else {
      return nil
    }
    
    if let genericBase = genericParameters[base.text] {
      if let text = genericBase?.identifier {
        return "some " + text
      } else {
        return nil
      }
    }
    var substituted = base.text
    
    while let token = iterator.next() {
      switch token.tokenKind {
      case .leftAngle:
        substituted += "<"
      case .rightAngle:
        substituted += ">"
      case .comma:
        substituted += ","
      case .identifier(let identifier):
        let type: TypeSyntax = "\(raw: identifier)"
        guard let substituedType = type.genericSubstitution(parameters) else {
          return nil
        }
        substituted += substituedType
        break
      default:
        // ignore?
        break
      }
    }
    
    return substituted
  }
  
}

extension FunctionDeclSyntax {
  
  internal var isInstance: Bool {
    if let modifiers {
      for modifier in modifiers {
        for token in modifier.tokens(viewMode: .all) {
          if token.tokenKind == .keyword(.static) || token.tokenKind == .keyword(.class) {
            return false
          }
        }
      }
    }
    return true
  }
  
  internal struct SignatureStandin: Equatable {
    var isInstance: Bool
    var identifier: String
    var parameters: [String]
    var returnType: String
  }
  
  internal var signatureStandin: SignatureStandin {
    var parameters = [String]()
    for parameter in signature.input.parameterList {
      parameters.append(parameter.firstName.text + ":" + (parameter.type.genericSubstitution(genericParameterClause?.genericParameterList) ?? "" ))
    }
    let returnType = signature.output?.returnType.genericSubstitution(genericParameterClause?.genericParameterList) ?? "Void"
    return SignatureStandin(isInstance: isInstance, identifier: identifier.text, parameters: parameters, returnType: returnType)
  }
  
  internal func isEquivalent(to other: FunctionDeclSyntax) -> Bool {
    return signatureStandin == other.signatureStandin
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

extension TypeSyntax {
  
  internal var identifier: String? {
    for token in tokens(viewMode: .all) {
      switch token.tokenKind {
      case .identifier(let identifier):
        return identifier
      default:
        break
      }
    }
    return nil
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

extension DeclGroupSyntax {
  
  internal func hasMemberFunction(equvalentTo other: FunctionDeclSyntax) -> Bool {
    for member in memberBlock.members {
      if let function = member.as(MemberDeclListItemSyntax.self)?.decl.as(FunctionDeclSyntax.self) {
        if function.isEquivalent(to: other) {
          return true
        }
      }
    }
    return false
  }
  
  internal func hasMemberProperty(equivalentTo other: VariableDeclSyntax) -> Bool {
    for member in memberBlock.members {
      if let variable = member.as(MemberDeclListItemSyntax.self)?.decl.as(VariableDeclSyntax.self) {
        if variable.isEquivalent(to: other) {
          return true
        }
      }
    }
    return false
  }
  
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
  
  internal func addIfNeeded(_ decl: DeclSyntax?, to declarations: inout [DeclSyntax]) {
    guard let decl else { return }
    if let fn = decl.as(FunctionDeclSyntax.self) {
      if !hasMemberFunction(equvalentTo: fn) {
        declarations.append(decl)
      }
    } else if let property = decl.as(VariableDeclSyntax.self) {
      if !hasMemberProperty(equivalentTo: property) {
        declarations.append(decl)
      }
    } else if let `struct` = decl.as(StructDeclSyntax.self) {
      if !hasMemberStruct(equivalentTo: `struct`) {
        declarations.append(decl)
      }
    }
  }
  
  internal var isStruct: Bool {
    return self.is(StructDeclSyntax.self)
  }
  
  internal var isClass: Bool {
    return self.is(ClassDeclSyntax.self)
  }
  
  internal var isActor: Bool {
    return self.is(ActorDeclSyntax.self)
  }
  
  internal var isEnum: Bool {
    return self.is(EnumDeclSyntax.self)
  }
  
}
