//
//  COWExpansionFactory.swift
//
//
//  Created by WeZZard on 8/22/23.
//

import SwiftSyntax
import SwiftSyntaxMacros

@_implementationOnly import SwiftSyntaxBuilder
@_implementationOnly import SwiftDiagnostics

internal class COWExpansionFactory<Context: MacroExpansionContext> {
  
  internal let node: AttributeSyntax
  
  internal let context: Context
  
  internal let appliedStructDecl: StructDeclSyntax
  
  internal let appliedStructInitializedVarDecls: [VariableDeclSyntax]
  
  internal let appliedStructTypeAnnotatedVarDecls: [VariableDeclSyntax]
  
  internal let appliedStructInvalidVarDecls: [VariableDeclSyntax]
  
  private var userStorageTypeDecl: StructDeclSyntax?
  
  private var userStorageTypeAnnotatedVarDecls: [VariableDeclSyntax]?
  
  private var diagnosticsErrors: [DiagnosticsError]
  
  private func report(_ diagnosticsError: DiagnosticsError) {
    diagnosticsErrors.append(diagnosticsError)
  }
  
  internal func diagnose() -> Bool {
    if diagnosticsErrors.isEmpty {
      return false
    }
    for eachError in diagnosticsErrors {
      for eachDiagnostic in eachError.diagnostics {
        context.diagnose(eachDiagnostic)
      }
    }
    return true
  }
  
  internal var hasUserStorage: Bool {
    return userStorageTypeDecl != nil
  }
  
  private var appliedStructValidVarDecls: [VariableDeclSyntax] {
    return appliedStructInitializedVarDecls
      + appliedStructTypeAnnotatedVarDecls
  }
  
  private var hasTypedAnnotatedVarDeclsInUserStorage: Bool {
    return userStorageTypeAnnotatedVarDecls?.isEmpty == false
  }
  
  internal init(
    node: AttributeSyntax,
    context: Context,
    appliedStructDecl: StructDeclSyntax
  ) {
    self.node = node
    self.context = context
    self.appliedStructDecl = appliedStructDecl
    (
      self.appliedStructInitializedVarDecls,
      self.appliedStructTypeAnnotatedVarDecls,
      self.appliedStructInvalidVarDecls
    ) = appliedStructDecl.classifiedAdoptableVarDecls
    self.diagnosticsErrors = []
    self.checkAppliedStruct()
  }
  
  internal func setUserDefinedStorageTypeDecls(_ decls: [StructDeclSyntax]) {
    guard decls.count <= 1 else {
      for eachDecl in decls {
        report(
          DiagnosticsError(
           syntax: eachDecl,
           message:
             """
             Only one subtyped struct can be marked with @COWStorage in a \
             @COW marked struct.
             """,
           id: .duplicateCOWStorages
         )
        )
      }
      return
    }
    
    if let storageTypeDecl = decls.first {
      self.userStorageTypeDecl = storageTypeDecl
      self.userStorageTypeAnnotatedVarDecls =
        storageTypeDecl.classifiedAdoptableVarDecls.validWithTypeAnnoation
    }
  }
  
  typealias StorageTypeAndAssociatedMembers = (
    storageType: StructDeclSyntax,
    additionalMembers: [DeclSyntax]?
  )
  
  internal func getStorageTypeDecl() -> StorageTypeAndAssociatedMembers {
    if let userStorageTypeDecl {
      return (userStorageTypeDecl, nil)
    }
    
    return createDerivedStorageTypeDecl()
  }
  
  internal var hasDefaultInitializerInStorage: Bool {
    return appliedStructTypeAnnotatedVarDecls.isEmpty
      && !hasTypedAnnotatedVarDeclsInUserStorage
  }
  
  internal var hasAnyAdoptableProperties: Bool {
    return !appliedStructInitializedVarDecls.isEmpty
      || !appliedStructTypeAnnotatedVarDecls.isEmpty
  }
  
  internal func createStorageVarDecl(
    memberName: TokenSyntax,
    typeName: TokenSyntax,
    hasDefaultInitializer: Bool
  ) -> DeclSyntax {
    if hasDefaultInitializer {
      return
        """
        @\(raw: COWExcludedMacro.name)
        @\(_Box.type)
        var \(memberName): \(typeName) = \(typeName)()
        """
    } else {
      return
        """
        @\(raw: COWExcludedMacro.name)
        @\(_Box.type)
        var \(memberName): \(typeName)
        """
    }
  }
  
  internal func createExplicitInitializerDeclIfNeeded(
    storageTypeDecl: StructDeclSyntax,
    storageName: TokenSyntax
  ) -> InitializerDeclSyntax? {
    
    guard !appliedStructTypeAnnotatedVarDecls.isEmpty
            || userStorageTypeAnnotatedVarDecls?.isEmpty == false else {
      return nil
    }
    
    let explicitInitializers =
      appliedStructDecl.collectExplicitInitializerDecls()
    
    let parameters = collectExplicitInitParameters(
      storageTypeDecl: storageTypeDecl
    )
    
    guard explicitInitializers.isEmpty else {
      checkExplicitInitializers(
        explicitInitializers,
        storageName: storageName,
        storageTypeName: storageTypeDecl.name,
        parameters: parameters
      )
      return nil
    }
    
    let parameterList = FunctionParameterListSyntax(parameters)
    let parameterClause = FunctionParameterClauseSyntax(parameters: parameterList)
    let signature = FunctionSignatureSyntax(parameterClause: parameterClause)
    return InitializerDeclSyntax(signature: signature) {
      createInitStorageExpr(
        storageName: storageName,
        storageTypeName: storageTypeDecl.name,
        parameters: parameters,
        usesTemplateArguments: false
      )
    }
  }
  
  internal func createInitStorageExpr(
    storageName: TokenSyntax,
    storageTypeName: TokenSyntax,
    parameters: [FunctionParameterSyntax],
    usesTemplateArguments: Bool
  ) -> SequenceExprSyntax {
    // SwiftParser diagnoses errors for editor placeholders generated by
    // `createArgListSyntax` and cannot supress. We build the following syntax
    // with syntax builder here.
    // self.$storageName = $makeStorageName(...parameters)
    return SequenceExprSyntax {
      MemberAccessExprSyntax(
        base: DeclReferenceExprSyntax(baseName: .keyword(.self)),
        period: .periodToken() ,
        declName: DeclReferenceExprSyntax(baseName: storageName)
      )
      .with(\.trailingTrivia, .space)
      AssignmentExprSyntax()
      .with(\.trailingTrivia, .space)
      FunctionCallExprSyntax(
        calledExpression: DeclReferenceExprSyntax(
          baseName: storageTypeName.trimmed
        )
      ) {
        LabeledExprListSyntax.makeArgList(
          parameters: parameters,
          usesTemplateArguments: usesTemplateArguments
        )
      }
      .with(\.leftParen, .leftParenToken())
      .with(\.rightParen, .rightParenToken())
    }
  }
  
  // MARK: Utilities
  
  // If `appliedStructDecl` conforms to Equatable and manually implements `==`,
  // the derived storage must also conform to Equatable (otherwise we hit a
  // compiler bug that breaks the build).
  // https://forums.swift.org/t/macro-multiple-matching-functions-xyz-error-though-the-expanded-code-has-no-duplicate-functions-and-compiles/68700/4
  // FIXME: remove the workaround when the compiler bug is fixed.
  private func applyEquatableWorkaroundIfNeeded(
    members: inout [MemberBlockItemSyntax],
    protocols: inout [InheritedTypeSyntax]
  ) {
    // Bail out if derived storage doesn't conform to Equatable.
    guard protocols.contains(where: {
      guard let name = $0.type.identifier else {
        return false
      }
      return equatableProtocolNames.contains(name) ||
             hashableProtocolNames.contains(name)
    }) else {
      return
    }
    
    // Bail out if `appliedStructDecl` does not manually implement `==`.
    guard let nestingEqualFunc = appliedStructDecl.memberBlock.members
      .lazy
      .map(\.decl)
      .compactMap({$0.as(FunctionDeclSyntax.self)})
      .first(where: {$0.likelyToConformToEquatable(for: appliedStructDecl)}) else {
      return
    }
    
    // Another compiler bug another workaround.
    // The compiler doesn't call the manually-implemented `==` in `appliedStructDecl`;
    // it will synthesize one for the derived storage and call it instead.
    // Expand an `==` that is an exact copy (except for the signature) of
    // `appliedStructDecl` to make sure the program behavior is correct.
    
    // In order to make this workaround work with computed properties and
    // immutable functions with return values, we also have to copy them into
    // the derived storage.
    appliedStructDecl.memberBlock.members
      .lazy
      .map(\.decl)
      .compactMap { $0.as(VariableDeclSyntax.self) }
      .filter { !$0.isStatic && !$0.isStored }
      .forEach { members.append(MemberBlockItemSyntax(decl: $0)) }
    appliedStructDecl.memberBlock.members
      .lazy
      .map(\.decl)
      .compactMap { $0.as(FunctionDeclSyntax.self) }
      .filter { !$0.isStatic && !$0.isMutating && !$0.returnTypeEquals(to: "Void") }
      .forEach { members.append(MemberBlockItemSyntax(decl: $0)) }
    
    members.append(
      MemberBlockItemSyntax(
        decl: createEqualForEquatableWorkaround(nestingEqualFunc: nestingEqualFunc)
      )
    )
    
    // Yet another compiler bug and another workaround :)
    // https://github.com/apple/swift/issues/66348
    // The compiler does not recognize expanded `==` as a conformance which is
    // fixed in Swift 5.9.2.
    // For clients still using older compilers, work around by conforming a
    // proxy protocol. Idea credits to
    // https://github.com/JosephDuffy/HashableMacro/commit/250787664a63ceff83c1c9b5e30e574ada568f2f.
    #if swift(<5.9.2)
    let equalsProxyProtocol: TypeSyntax = "COW.COWStorageEquatableWorkaround"
    protocols.append(InheritedTypeSyntax(type: equalsProxyProtocol))
    #endif
  }
  
  private func createEqualForEquatableWorkaround(
    nestingEqualFunc: FunctionDeclSyntax
  ) -> FunctionDeclSyntax {
    // Use signature from proxy protocol if needed. See the comments about why
    // we are adding a proxy protocol for the reason.
    #if swift(<5.9.2)
    let nestedEqualFuncName: TokenSyntax = "equalsWorkaround"
    #else
    let nestedEqualFuncName = nestingEqualFunc.name
    #endif
    return .init(
      attributes: nestingEqualFunc.attributes,
      modifiers: nestingEqualFunc.modifiers,
      name: nestedEqualFuncName,
      genericParameterClause: nestingEqualFunc.genericParameterClause,
      signature: nestingEqualFunc.signature,
      genericWhereClause: nestingEqualFunc.genericWhereClause,
      body: nestingEqualFunc.body
    )
  }
  
  private func forwardCodingKeysForDerivedStorageIfNeeded(
    members: inout [MemberBlockItemSyntax],
    protocols: inout [InheritedTypeSyntax],
    associatedMembers: inout [DeclSyntax]
  ) {
    // Bail out early if `appliedStructDecl` does not declare CodingKeys.
    guard appliedStructDecl.memberBlock.members.contains(where: {
      if let enumDecl = $0.decl.as(EnumDeclSyntax.self),
         enumDecl.name.trimmed.text == "CodingKeys",
         let inheritedTypes = enumDecl.inheritanceClause?.inheritedTypes,
         inheritedTypes.containsType(named: "CodingKey") {
        return true
      }
      // We have no way to check the aliased type, so just make a guess (that
      // it is indeed a CodingKeys enum).
      if let typealiasDecl = $0.decl.as(TypeAliasDeclSyntax.self),
         typealiasDecl.name.trimmed.text == "CodingKeys" {
        return true
      }
      return false
    }) else {
      return
    }
    
    // Bail out early if we are not conforming to anything Codable related.
    let conformingToCodable = protocols.contains(where: {
      guard let name = $0.type.identifier else {
        return false
      }
      return codableProtocolNames.contains(name)
    })
    let conformingToEncodable = conformingToCodable || protocols.contains(where: {
      guard let name = $0.type.identifier else {
        return false
      }
      return encodableProtocolNames.contains(name)
    })
    let conformingToDecodable = conformingToCodable || protocols.contains(where: {
      guard let name = $0.type.identifier else {
        return false
      }
      return decodableProtocolNames.contains(name)
    })
    guard conformingToCodable ||
          conformingToEncodable ||
          conformingToDecodable else {
      return
    }
    
    // Make a typealias in the derived storage pointing to the CodingKeys in
    // `appliedStructDecl` which allow the compiler to synthesize the actual
    // coding functions.
    let typealiasDecl: DeclSyntax = """
    typealias CodingKeys = \(appliedStructDecl.name).CodingKeys
    """
    members.append(MemberBlockItemSyntax(decl: typealiasDecl))
    
    // Expand coding functions in `appliedStructDecl`, forwarding the
    // invocation to the derived storage.
    if conformingToEncodable {
      let encodeForwarder: DeclSyntax = """
      func encode(to encoder: any Encoder) throws {
        try \(defaultStorageName).encode(to: encoder)
      }
      """
      associatedMembers.append(encodeForwarder)
    }
    if conformingToDecodable {
      let decodeForwarder: DeclSyntax = """
      init(from decoder: any Decoder) throws {
        self.\(defaultStorageName) = try \(defaultStorageTypeName)(from: decoder)
      }
      """
      associatedMembers.append(decodeForwarder)
    }
  }
  
  private func createDerivedStorageTypeDecl() -> StorageTypeAndAssociatedMembers {
    var members = appliedStructValidVarDecls.map {
      return MemberBlockItemSyntax(decl: $0)
    }
    
    var protocols = appliedStructDecl.collectAutoSynthesizingProtocolConformance()
    applyEquatableWorkaroundIfNeeded(members: &members, protocols: &protocols)
    
    var associatedMembers = [DeclSyntax]()
    forwardCodingKeysForDerivedStorageIfNeeded(
        members: &members,
        protocols: &protocols,
        associatedMembers: &associatedMembers
    )
    
    let inheritance = InheritanceClauseSyntax {
      InheritedTypeListSyntax {
        InheritedTypeSyntax(type: CopyOnWriteStorage.type)
      }
      // Equatable, Hashable, Codeable
      InheritedTypeListSyntax(
        protocols
      )
    }
    
    return (
      StructDeclSyntax(
        name: defaultStorageTypeName,
        inheritanceClause: inheritance
      ) {
        MemberBlockItemListSyntax(members)
      },
      associatedMembers
    )
  }
  
  private func collectExplicitInitParameters(
    storageTypeDecl: StructDeclSyntax
  ) -> [FunctionParameterSyntax] {
    
    let storageExplicitInitDecls =
      storageTypeDecl.collectExplicitInitializerDecls()
    
    let parameters: [FunctionParameterSyntax]
    
    if storageExplicitInitDecls.isEmpty {
      var allVars: [VariableDeclSyntax] = []
      
      allVars.append(contentsOf: appliedStructTypeAnnotatedVarDecls)
      if let userStorageTypeAnnotatedVarDecls {
        allVars.append(contentsOf: userStorageTypeAnnotatedVarDecls)
      }
      
      parameters = allVars.compactMap {
        varDecl -> FunctionParameterSyntax? in
        
        guard let ident = varDecl.identifier else {
          return nil
        }
        let firstBinding = varDecl.bindings[varDecl.bindings.startIndex]
        guard let typeAnnotation = firstBinding.typeAnnotation else {
          return nil
        }
        // Infer @escaping for function types.
        if typeAnnotation.type.is(FunctionTypeSyntax.self) {
          return
            """
            \(ident): @escaping \(typeAnnotation.type)
            """
        } else {
          return
            """
            \(ident): \(typeAnnotation.type)
            """
        }
      }
    } else if storageExplicitInitDecls.count == 1 {
      let funcSig = storageExplicitInitDecls[0].signature
      parameters = funcSig.parameterClause.parameters.map({$0})
    } else {
      for eachInitDecl in storageExplicitInitDecls {
        report(
          DiagnosticsError(
            syntax: eachInitDecl,
            message:
              """
              Declaring multiple initializers on @COWStorage applied struct is
              an undefined behavior.
              """,
            id: .undefinedBehavior
          )
        )
      }
      parameters = []
    }
    
    if parameters.count > 1 {
      var commaSeparatedParameters = [FunctionParameterSyntax]()
      for (index, eachParameter) in parameters.enumerated() {
        if (index + 1) < parameters.count {
          commaSeparatedParameters.append(
            eachParameter
              .with(\.trailingComma, .commaToken(trailingTrivia: .space))
          )
        } else {
          commaSeparatedParameters.append(eachParameter)
        }
      }
      return commaSeparatedParameters
    }
    
    return parameters
  }
  
  // MARK: Inputs Checking
  
  private func checkAppliedStruct() {
    guard !appliedStructInvalidVarDecls.isEmpty else {
      return
    }
    
    let illMembers = appliedStructDecl.memberBlock.members
    
    guard !illMembers.isEmpty else {
      return
    }
    
    var fixedMembers = illMembers
    
    typealias Replacement = (MemberBlockItemListSyntax.Index, [MemberBlockItemSyntax])
    var replacements: [Replacement] = []
    
    for eachInvalidVarDecl in appliedStructInvalidVarDecls {
      
      for index in illMembers.indices {
        let eachMember = illMembers[index]
        
        guard let varDecl = eachMember.decl.as(VariableDeclSyntax.self) else {
          continue
        }
        
        if varDecl.isEquivalent(to: eachInvalidVarDecl) {
          
          let fixedVarsDecls = eachInvalidVarDecl.bindings.map { binding in
            let fixedBinding = binding
              .with(\.trailingComma, nil)
            return eachInvalidVarDecl
              .with(\.bindings, PatternBindingListSyntax([fixedBinding]))
          }
          
          let fixedItems = fixedVarsDecls.map({
            MemberBlockItemSyntax(decl: $0)
              .with(\.leadingTrivia, eachMember.leadingTrivia)
              .with(\.trailingTrivia, eachMember.trailingTrivia)
          })
          
          replacements.append((index, fixedItems))
        }
        
      }
      
    }
    
    for (index, items) in replacements.reversed() {
      let replaceEnd = fixedMembers.index(after: index)
      fixedMembers.replaceSubrange(index..<replaceEnd, with: items)
    }
    
    report(
      DiagnosticsError(
        syntax: appliedStructDecl,
        message:
            """
            Decalring multiple stored properties over one variable declaration \
            is an undefined behavior for the @COW macro.
            """,
        fixIts:
            """
            Split the variable decalrations with multiple variable bindings into \
            seperate decalrations.
            """,
        changes: [
          .replace(oldNode: Syntax(illMembers), newNode: Syntax(fixedMembers))
        ],
        id: .undefinedBehavior,
        severity: .error
      )
    )
  }
  
  private func checkExplicitInitializers(
    _ initializers: [InitializerDeclSyntax],
    storageName: TokenSyntax,
    storageTypeName: TokenSyntax,
    parameters: [FunctionParameterSyntax]
  ) {
    for eachInit in initializers {
      checkStorageIsInitialized(
        in: eachInit,
        storageName: storageName,
        storageTypeName: storageTypeName,
        parameters: parameters
      )
    }
  }
  
  private func checkStorageIsInitialized(
    in initializer: InitializerDeclSyntax,
    storageName: TokenSyntax,
    storageTypeName: TokenSyntax,
    parameters: [FunctionParameterSyntax]
  ) {
    // Do not check convenient initializers.
    guard !initializer.isConvenient else {
      return
    }
    guard let body = initializer.body else {
      return
    }
    for eachStmt in body.statements {
      guard case .expr(let expr) = eachStmt.item else {
        continue
      }
      
      guard let seqExpr = expr.as(SequenceExprSyntax.self) else {
        continue
      }
      guard seqExpr.elements.count == 3 else {
        continue
      }
      
      let i1 = seqExpr.elements.startIndex
      let i2 = seqExpr.elements.index(i1, offsetBy: 1)
      
      let expr1 = seqExpr.elements[i1]
      let expr2 = seqExpr.elements[i2]
      
      guard let storage = expr1.as(MemberAccessExprSyntax.self) else {
        continue
      }
      let storageBase = storage.base?.as(DeclReferenceExprSyntax.self)?.baseName
      guard storageBase?.tokenKind == .keyword(.self) else {
        continue
      }
      guard storage.declName.baseName.tokenKind == storageName.tokenKind else {
        continue
      }
      guard let _ = expr2.as(AssignmentExprSyntax.self) else {
        continue
      }
      return
    }
    
    let initStorage = createInitStorageExpr(
        storageName: storageName,
        storageTypeName: storageTypeName,
        parameters: parameters,
        usesTemplateArguments: true
      )
    
    let fixedItems = [CodeBlockItemSyntax(item: .expr(ExprSyntax(initStorage)))]
      + Array(body.statements)
    
    let fixedStmts = CodeBlockItemListSyntax(fixedItems)
    
    report(
      DiagnosticsError(
        syntax: initializer,
        message:
          """
          @COW macro requires you to initialize the copy-on-write storage before \
          initializing the properties.
          """,
        fixIts: "Initializes copy-on-write storage to make the @COW macro work.",
        changes: [
          FixIt.Change.replace(
            oldNode: Syntax(body.statements),
            newNode: Syntax(fixedStmts)
          )
        ],
        id: .requiresManuallyInitializeStorage,
        severity: .error
      )
    )
  }
  
}
