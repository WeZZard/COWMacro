//
//  SyntaxExtensions.swift
//
//
//  Created by WeZZard on 7/1/23.
//

import SwiftSyntax

extension StructDeclSyntax {
  
  internal func hasMacroApplication(_ name: String) -> Bool {
    guard let attributes else {
      return false
    }
    for each in attributes where each.hasAttribute(name) {
      return true
    }
    return false
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
  
  internal var isValidForBeingIncludedInCOWStorage: Bool {
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
    for each in attributes where each.hasAttribute(name) {
      return true
    }
    return false
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
  internal func hasAttribute(_ name: String) -> Bool {
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
  
  internal var storageMemberName: TokenSyntax? {
    guard case .argumentList(let args) = self else {
      return nil
    }
    
    guard let storageSyntax = args.first?.as(StringLiteralExprSyntax.self) else {
      return nil
    }
    
    for each in storageSyntax.segments {
      if case .stringSegment(let seg) = each {
        return seg.content
      }
    }
    
    return nil
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
