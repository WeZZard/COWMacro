import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

@_implementationOnly import SwiftSyntaxBuilder
@_implementationOnly import SwiftDiagnostics

private let defaultStorageName: TokenSyntax = "_$storage"

// MARK: - NameLookupable

internal protocol NameLookupable {
  
  static var name: String { get }
  
  static var qualifiedName: String { get }
  
  static var type: TypeSyntax { get }
  
}

extension NameLookupable {
  
  internal static var moduleName: String {
    return "COW"
  }
  
  internal static var qualifiedName: String {
    return "\(moduleName).\(name)"
  }
  
  internal static var type: TypeSyntax {
    return "\(raw: qualifiedName)"
  }
  
}

internal struct _Box: NameLookupable {
  
  internal static var name: String {
    "_Box"
  }
  
}

internal struct CopyOnWriteStorage: NameLookupable {
  
  internal static var name: String {
    "CopyOnWriteStorage"
  }
  
}

// MARK: - @COW

public struct COWMacro:
  MemberMacro,
  MemberAttributeMacro,
  NameLookupable
{
  // MARK: NameLookupable
  
  internal static var name: String {
    "COW"
  }
  
  // MARK: MemberMacro
  
  public static func expansion<
    Declaration: DeclGroupSyntax,
    Context: MacroExpansionContext
  >(
    of node: AttributeSyntax,
    providingMembersOf declaration: Declaration,
    in context: Context
  ) throws -> [DeclSyntax] {
    
    let structDecl = try getStructDecl(
      from: declaration,
      attributedBy: node
    )
    
    let (initVarDecls, typeAnnoatedVarDecls) =
      try classifyIncludeableVarDecls(in: structDecl)
    
    // Create storage type
    guard let (storageTypeDecl, isUserDefinedStorage) =
            try createOrUseExistedStorageTypeDecl(
              for: structDecl,
              initVarDecls: initVarDecls,
              typeAnnoatedVarDecls: typeAnnoatedVarDecls,
              in: context
            ) else {
      return []
    }
    
    let storageName = structDecl.copyOnWriteStorageName
    ?? defaultStorageName
    
    // Create storage member
    let storageMemberDecl = createStorageMemberDecl(
      memberName: storageName,
      typeName: storageTypeDecl.typeName,
      hasInitializer: typeAnnoatedVarDecls.isEmpty
    )
    
    // Create explicit initializer if needed
    let explicitInitializerDecl = try createExplicitInitializerDeclIfNeeded(
      for: structDecl,
      expandedBy: node,
      storageTypeDecl: storageTypeDecl,
      isUserDefinedStorage: isUserDefinedStorage,
      storageName: storageName,
      typeAnnoatedVarDecls: typeAnnoatedVarDecls
    )
    
    var expansions = [DeclSyntax]()
    
    structDecl.addIfNeeded(storageTypeDecl, to: &expansions)
    structDecl.addIfNeeded(storageMemberDecl, to: &expansions)
    if let explicitInitializerDecl {
      structDecl.addIfNeeded(explicitInitializerDecl, to: &expansions)
    }
    
    return expansions
  }
  
  // MARK: MemberAttributeMacro
  
  public static func expansion<
    Declaration: DeclGroupSyntax,
    MemberDeclaration: DeclSyntaxProtocol,
    Context: MacroExpansionContext
  >(
    of node: AttributeSyntax,
    attachedTo declaration: Declaration,
    providingAttributesFor member: MemberDeclaration,
    in context: Context
  ) throws -> [AttributeSyntax] {
    
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      return []
    }
    
    let storageName = structDecl.copyOnWriteStorageName ?? defaultStorageName
    
    if let varDecl = member.as(VariableDeclSyntax.self) {
      // Marks non-`@COWExcluded` stored properties with `@COWIncldued`
      
      guard varDecl.isIncludeable else {
        return []
      }
      
      return [
        "@\(raw: COWIncludedMacro.name)(storageName: \"\(storageName)\")",
      ]
      
    } else if let memberStructDecl = member.as(StructDeclSyntax.self) {
      // Marks `@COWStorage` sub struct with `@COWStorageAddProperty`
      
      guard memberStructDecl.hasMacroApplication(COWStorageMacro.name) else {
        return []
      }
      
      let storedVarDecls = collectStoredVarDecls(on: memberStructDecl)
      var validIncludeableVarDecls = collectIncludeableVarDecls(
        on: structDecl
      ).filter(\.hasSingleBinding)
      
      // Get var decls in user storage type decl
      // Remove equivalents in include-able var decls
      
      for (index, eachVar) in validIncludeableVarDecls.enumerated().reversed() {
        for eachStoredVar in storedVarDecls {
          if eachVar.isEquivalent(to: eachStoredVar) {
            validIncludeableVarDecls.remove(at: index)
          }
        }
      }
      
      guard !validIncludeableVarDecls.isEmpty else {
        return []
      }
      
      let result = validIncludeableVarDecls.map { eachVarDecl -> [AttributeSyntax] in
        eachVarDecl.storagePropertyDescriptors.map { desc -> AttributeSyntax in
          AttributeSyntax(TypeSyntax(SimpleTypeIdentifierSyntax(name: .identifier(COWStorageAddPropertyMacro.name)))) {
            TupleExprElementSyntax(label: "keyword", expression: MemberAccessExprSyntax(name: desc.keyword.trimmed))
            TupleExprElementSyntax(label: "name", expression: StringLiteralExprSyntax(content: desc.name.text))
            if let type = desc.type {
              TupleExprElementSyntax(label: "type", expression: StringLiteralExprSyntax(content: type.trimmedDescription))
            }
            if let initializer = desc.initializer {
              TupleExprElementSyntax(label: "initialValue", expression: StringLiteralExprSyntax(content: initializer.trimmedDescription))
            }
          }
        }
      }.flatMap({$0})
      
      
      return result
    }
    
    return []
  }
  
}

extension COWMacro {
  
  internal static func getStructDecl<Declaration: DeclGroupSyntax>(
    from declaration: Declaration,
    attributedBy node: AttributeSyntax
  ) throws -> StructDeclSyntax {
    guard let identifiedDecl
            = declaration.asProtocol(IdentifiedDeclSyntax.self) else {
      throw DiagnosticsError(
        syntax: node,
        message:
        """
        @COW applied on an non-identified decl syntax \(declaration). \
        This should be considered as a bug in compiler or the COW macro \
        compiler plugin.
        """,
        id: .internalInconsistency
      )
    }
    
    let appliedType = identifiedDecl.identifier
    
    if declaration.isEnum {
      throw DiagnosticsError(
        syntax: node,
        message: "@COW cannot be applied to enum type \(appliedType.text)",
        id: .invalidType
      )
    }
    if declaration.isClass {
      // enumerations cannot store properties
      throw DiagnosticsError(
        syntax: node,
        message: "@COW cannot be applied to class type \(appliedType.text)",
        id: .invalidType
      )
    }
    if declaration.isActor {
      // actors cannot yet be supported for their isolation
      throw DiagnosticsError(
        syntax: node,
        message: "@COW cannot be applied to actor type \(appliedType.text)",
        id: .invalidType
      )
    }
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      // Swift may introduce other keywords that is parallel to `enum`,
      // `class` and `actor` in the future.
      throw DiagnosticsError(
        syntax: node,
        message:
          """
          @COW cannot be applied to non-struct type \(appliedType.text)
          """,
        id: .invalidType
      )
    }
    
    return structDecl
  }
  
  internal static func collectUserDefinedStorageTypeDecls<
    Declaration: DeclGroupSyntax
  >(in declaration: Declaration) -> [StructDeclSyntax] {
    return declaration.memberBlock.members.compactMap { eachItem in
      guard let structDecl = eachItem.decl.as(StructDeclSyntax.self),
            structDecl.hasMacroApplication(COWStorageMacro.name) else {
        return nil
      }
      return structDecl
    }
  }
  
  internal static func collectIncludeableVarDecls<
    Declaration: DeclGroupSyntax
  >(on declaration: Declaration) -> [VariableDeclSyntax] {
    return declaration.memberBlock.members.compactMap {
      eachItem -> VariableDeclSyntax? in
      guard let varDecl = eachItem.decl.as(VariableDeclSyntax.self),
            varDecl.isIncludeable else {
        return nil
      }
      return varDecl.trimmed
    }
  }
  
  internal static func collectStoredVarDecls<Declaration: DeclGroupSyntax>(
    on declaration: Declaration
  ) -> [VariableDeclSyntax] {
    return declaration.memberBlock.members.compactMap { eachItem in
      guard let varDecl = eachItem.decl.as(VariableDeclSyntax.self),
            varDecl.bindings.allSatisfy(\.isStored) else {
        return nil
      }
      return varDecl.trimmed
    }
  }
  
  internal static func classifyIncludeableVarDecls<
    Declaration: DeclGroupSyntax
  >(
    in declaration: Declaration
  ) throws -> (
    validWithInitializer: [VariableDeclSyntax],
    validWithTypeAnnoation: [VariableDeclSyntax]
  ) {
    let collectedVarDecls = collectIncludeableVarDecls(on: declaration)
    
    let validVarDecls = collectedVarDecls
      .filter(\.hasSingleBinding)
    let validWithInitializer = validVarDecls
      .filter(\.bindings.first!.hasInitializer)
    let validWithTypeAnnoation = validVarDecls
      .filter(\.bindings.first!.hasNoInitializer)
    let invalidVarDecls = collectedVarDecls
      .filter(\.hasMultipleBindings)
    
    if !invalidVarDecls.isEmpty {
      let oldMembers = declaration.memberBlock.members
      
      var newMembers = declaration.memberBlock.members
      
      for eachInvalid in invalidVarDecls {
        for (index, eachMember) in newMembers.enumerated().reversed() {
          guard let varDecl = eachMember.decl.as(VariableDeclSyntax.self) else {
            continue
          }
          if varDecl.isEquivalent(to: eachInvalid) {
            let allReplaced = eachInvalid.bindings.map { eachBinding in
              let fixedBinding = eachBinding
                .with(\.trailingComma, nil)
              return eachInvalid
                .with(\.bindings, PatternBindingListSyntax([fixedBinding]))
                .with(\.leadingTrivia, .newline)
            }
            newMembers = newMembers.removing(childAt: index)
            for eachReplaced in allReplaced.reversed() {
              newMembers = newMembers.inserting(
                MemberDeclListItemSyntax(decl: eachReplaced), at: index
              )
            }
          }
        }
      }
      
      throw DiagnosticsError.init(
        syntax: oldMembers,
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
          .replace(oldNode: Syntax(oldMembers), newNode: Syntax(newMembers))
        ],
        id: .undefinedBehavior,
        severity: .error
      )
    }
    
    return (
      validWithInitializer,
      validWithTypeAnnoation
    )
  }
  
  internal static func createOrUseExistedStorageTypeDecl<
    Declaration: DeclGroupSyntax,
    Context: MacroExpansionContext
  >(
    for declaration: Declaration,
    initVarDecls: [VariableDeclSyntax],
    typeAnnoatedVarDecls: [VariableDeclSyntax],
    in context: Context
  ) throws -> (decl: StructDeclSyntax, isUserDefined: Bool)? {
    let decl: StructDeclSyntax
    let isUserDefined: Bool
    
    let userDefinedDecls = collectUserDefinedStorageTypeDecls(in: declaration)
    
    if userDefinedDecls.isEmpty {
      if initVarDecls.isEmpty && typeAnnoatedVarDecls.isEmpty {
        return nil
      }
      decl = self.createStorageTypeDecl(
        for: declaration,
        with: initVarDecls + typeAnnoatedVarDecls,
        in: context
      )
      isUserDefined = false
    } else if userDefinedDecls.count == 1 {
      decl = userDefinedDecls[0]
      isUserDefined = true
    } else {
      let secondUserStorageTypeDecl = userDefinedDecls[1]
      throw DiagnosticsError(
        syntax: secondUserStorageTypeDecl,
        message:
          """
          Only one subtyped struct can be marked with @COWStorage in a \
          @COW marked struct.
          """,
        id: .duplicateCOWStorages
      )
    }
    return (decl, isUserDefined)
  }
  
  internal static let autoSynthesizingProtocolTypes: Set<String> = [
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
  
  internal static func collectAutoSynthesizingProtocolConformance<
    Declaration: DeclGroupSyntax
  >(
    on declaration: Declaration
  ) -> [InheritedTypeSyntax] {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      return []
    }
    
    guard let inheritedTypes
            = structDecl.inheritanceClause?.inheritedTypeCollection else {
      return []
    }
    
    return inheritedTypes.filter { each in
      if let ident = each.typeName.identifier {
        if autoSynthesizingProtocolTypes.contains(ident) {
          return true
        }
      }
      return false
    }
  }
  
  internal static func createStorageTypeDecl<
    Declaration: DeclGroupSyntax,
    Context: MacroExpansionContext
  >(
    for declaration: Declaration,
    with varDecls: [VariableDeclSyntax],
    in context: Context
  ) -> StructDeclSyntax {
    let allMemebers = varDecls.map {
      MemberDeclListItemSyntax(decl: $0)
    }
    let inheritance = TypeInheritanceClauseSyntax {
      InheritedTypeListSyntax {
        InheritedTypeSyntax(typeName: CopyOnWriteStorage.type)
      }
      // Equatable, Hashable, Codeable
      InheritedTypeListSyntax(
        collectAutoSynthesizingProtocolConformance(on: declaration)
      )
    }
    let typeName: TokenSyntax = "_$COWStorage"
    return StructDeclSyntax(
      identifier: typeName,
      inheritanceClause: inheritance
    ) {
      MemberDeclListSyntax(allMemebers)
    }
  }
  
  internal static func createStorageMemberDecl(
    memberName: TokenSyntax,
    typeName: TokenSyntax,
    hasInitializer: Bool
  ) -> DeclSyntax {
    if hasInitializer {
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
  
  internal static func collectStorageInitParameters(
    node: AttributeSyntax,
    storageTypeDecl: StructDeclSyntax,
    isUserDefinedStorage: Bool,
    typeAnnoatedVarDecls: [VariableDeclSyntax]
  ) throws -> [FunctionParameterSyntax] {
    let storageExplicitInitDecls = collectExplicitInitializers(
      on: storageTypeDecl
    )
    
    let parameters: [FunctionParameterSyntax]
    
    if storageExplicitInitDecls.isEmpty {
      var allVars: [VariableDeclSyntax] = []
      
      if isUserDefinedStorage {
        let existedVars = storageTypeDecl.memberBlock.members.compactMap {
          eachMember -> VariableDeclSyntax? in
          guard let eachVar = eachMember.decl.as(VariableDeclSyntax.self) else {
            return nil
          }
          return eachVar
        }
        allVars.append(contentsOf: existedVars)
      }
      
      allVars.append(contentsOf: typeAnnoatedVarDecls)
      
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
      // TODO: What about multiple explicit initializers on user defined storage?
      let funcSig = storageExplicitInitDecls[0].signature
      parameters = funcSig.input.parameterList.map({$0})
    } else {
      throw DiagnosticsError(
        syntax: node,
        message:
          """
          @COW macro cannot create the static make storage method on \
          behalf of you since there are multiple explicit initializers are \
          defined in the copy-on-write storage type declaration \
          \(storageTypeDecl.identifier.trimmed.text)
          """,
        id: .undefinedBehavior)
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
  
  internal static func collectExplicitInitializers<
    Declaration: DeclGroupSyntax
  >(on declaration: Declaration) -> [InitializerDeclSyntax] {
    return declaration.memberBlock.members.compactMap { eachItem in
      eachItem.decl.as(InitializerDeclSyntax.self)
    }
  }
  
  internal static func checkExplicitInitializers(
    _ initializers: [InitializerDeclSyntax],
    storageName: TokenSyntax,
    storageTypeName: TokenSyntax,
    parameters: [FunctionParameterSyntax]
  ) throws {
    for eachInit in initializers {
      try checkStorageIsInitialized(
        in: eachInit,
        storageName: storageName,
        storageTypeName: storageTypeName,
        parameters: parameters
      )
    }
  }
  
  internal static func createExplicitInitializerDeclIfNeeded<
    Declaration: DeclGroupSyntax
  >(
    for declaration: Declaration,
    expandedBy node: AttributeSyntax,
    storageTypeDecl: StructDeclSyntax,
    isUserDefinedStorage: Bool,
    storageName: TokenSyntax,
    typeAnnoatedVarDecls: [VariableDeclSyntax]
  ) throws -> InitializerDeclSyntax? {
    
    guard !typeAnnoatedVarDecls.isEmpty else {
      return nil
    }
    
    let explicitInitializers = collectExplicitInitializers(on: declaration)
    
    let parameters = try collectStorageInitParameters(
      node: node,
      storageTypeDecl: storageTypeDecl,
      isUserDefinedStorage: isUserDefinedStorage,
      typeAnnoatedVarDecls: typeAnnoatedVarDecls
    )
    
    guard explicitInitializers.isEmpty else {
      try checkExplicitInitializers(
        explicitInitializers,
        storageName: storageName,
        storageTypeName: storageTypeDecl.identifier,
        parameters: parameters
      )
      return nil
    }
    
    let parametersSynax = FunctionParameterListSyntax(parameters)
    
    let initDecl = try InitializerDeclSyntax("init(\(parametersSynax))") {
      createInitStorageExpr(
        storageName: storageName,
        storageTypeName: storageTypeDecl.identifier,
        parameters: parameters,
        usesTemplateArguments: false
      )
    }
    
    return initDecl
  }
  
  internal static func createInitStorageExpr(
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
        base: IdentifierExprSyntax(identifier: .keyword(.self)),
        dot: .periodToken() ,
        name: storageName
      )
      .with(\.trailingTrivia, .space)
      AssignmentExprSyntax()
      .with(\.trailingTrivia, .space)
      FunctionCallExprSyntax(
        calledExpression: IdentifierExprSyntax(
          identifier: storageTypeName.trimmed
        )
      ) {
        createArgListSyntax(
          parameters: parameters,
          usesTemplateArguments: usesTemplateArguments
        )
      }
      .with(\.leftParen, .leftParenToken())
      .with(\.rightParen, .rightParenToken())
    }
  }
  
  internal static func createArgListSyntax(
    parameters: [FunctionParameterSyntax],
    usesTemplateArguments: Bool
  ) -> TupleExprElementListSyntax {
    let parameterCount = parameters.count
    let args = parameters.enumerated().map {
      (index, eachParam) -> TupleExprElementSyntax in
      
      let label = eachParam.firstName
      let name = eachParam.secondName ?? eachParam.firstName
      let nameToken: TokenSyntax
      if usesTemplateArguments {
        nameToken = TokenSyntax(.identifier("<#\(name.text)#>"), presence: .present)
      } else {
        nameToken = name
      }
      var syntax = TupleExprElementSyntax(
        label: label.trimmed.text,
        expression: IdentifierExprSyntax(identifier: nameToken)
      ).with(\.colon, .colonToken(trailingTrivia: .spaces(1)))
      
      if parameterCount > 0 && (index + 1) < parameterCount {
        syntax = syntax
          .with(\.trailingComma, .commaToken(trailingTrivia: .spaces(1)))
      }
      
      return syntax
    }
    return TupleExprElementListSyntax(args)
  }
  
  internal static func checkStorageIsInitialized(
    in initializer: InitializerDeclSyntax,
    storageName: TokenSyntax,
    storageTypeName: TokenSyntax,
    parameters: [FunctionParameterSyntax]
  ) throws {
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
      let storageBase = storage.base?.as(IdentifierExprSyntax.self)?.identifier
      guard storageBase?.tokenKind == .keyword(.self) else {
        continue
      }
      guard storage.name.tokenKind == storageName.tokenKind else {
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
    
    let fixedStmts = body.statements
      .prepending(.init(item: .expr(ExprSyntax(initStorage))))
    
    throw DiagnosticsError(
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
  }
  
}

// MARK: - @COWIncluded

public struct COWIncludedMacro: AccessorMacro, NameLookupable {
  
  // MARK: - NameLookupable
  
  internal static var name: String {
    "COWIncluded"
  }
  
  public static func expansion<
    Context: MacroExpansionContext,
    Declaration: DeclSyntaxProtocol
  >(
    of node: AttributeSyntax,
    providingAccessorsOf declaration: Declaration,
    in context: Context
  ) throws -> [AccessorDeclSyntax] {
    guard let varDecl = declaration.as(VariableDeclSyntax.self),
          varDecl.isIncludeable,
          let identifier = varDecl.identifier else {
      return []
    }
    
    guard let storageName = node.argument?.storageName else {
      throw DiagnosticsError(
        syntax: node,
        message:
          """
          The macro @COWIncluded shall have storage name get specified.
          """,
        id: .internalInconsistency,
        severity: .error
      )
    }
    
    let getAccessor: AccessorDeclSyntax =
      """
      get {
        return \(storageName).\(identifier)
      }
      """
    
    let setAccessor: AccessorDeclSyntax =
      """
      set {
        \(storageName).\(identifier) = newValue
      }
      """
    
    return [
      getAccessor,
      setAccessor,
    ]
  }
  
}

// MARK: - @COWExcluded

public struct COWExcludedMacro: PeerMacro, NameLookupable {
  
  // MARK: - NameLookupable
  
  internal static var name: String {
    "COWExcluded"
  }
  
  // MARK: - PeerMacro
  
  public static func expansion<
    Declaration: DeclSyntaxProtocol,
    Context: MacroExpansionContext
  >(
    of node: AttributeSyntax,
    providingPeersOf declaration: Declaration,
    in context: Context
  ) throws -> [DeclSyntax] {
    return []
  }
  
}

// MARK: - @COWStorage

public struct COWStorageMacro: ConformanceMacro, NameLookupable {
  
  // MARK: - NameLookupable
  
  internal static var name: String {
    "COWStorage"
  }
  
  // MARK: - ConformanceMacro
  
  public static func expansion<
    Declaration : DeclGroupSyntax,
    Context : MacroExpansionContext
  >(
    of node: AttributeSyntax,
    providingConformancesOf declaration: Declaration,
    in context: Context
  ) throws -> [(TypeSyntax, GenericWhereClauseSyntax?)] {
    let inheritanceList: InheritedTypeListSyntax?
    
    if let structDecl = declaration.as(StructDeclSyntax.self) {
      inheritanceList = structDecl.inheritanceClause?.inheritedTypeCollection
    } else {
      inheritanceList = nil
    }
    
    if let inheritanceList {
      for inheritance in inheritanceList {
        if inheritance.typeName.identifier == CopyOnWriteStorage.name {
          return []
        }
      }
    }
    
    return [(CopyOnWriteStorage.type, nil)]
  }
  
}

// MARK: - @COWStorageAddProperty

public struct COWStorageAddPropertyMacro: MemberMacro, NameLookupable {
  
  // MARK: - NameLookupable
  
  internal static var name: String {
    "COWStorageAddProperty"
  }
  
  // MARK: - MemberMacro
  
  public static func expansion<
    Declaration: DeclGroupSyntax,
    Context: MacroExpansionContext
  >(
    of node: AttributeSyntax,
    providingMembersOf declaration: Declaration,
    in context: Context
  ) throws -> [DeclSyntax] {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      throw DiagnosticsError(
        syntax: node,
        message: "@COWStorageAddProperty can only be applied on struct types.",
        id: .invalidType
      )
    }
    
    guard structDecl.hasMacroApplication(COWStorageMacro.name) else {
      throw DiagnosticsError(
        syntax: node,
        message:
          """
          @COWStorageAddProperty can only be applied on @COWStorage marked \
          struct types.
          """,
        id: .requiresCOWStorage
      )
    }
    
    guard let arg = node.argument else {
      throw DiagnosticsError(
        syntax: node,
        message: "No argument found for macro @COWStorageAddProperty.",
        id: .internalInconsistency
      )
    }
    
    guard let descriptor = arg.storagePropertyDescriptor else {
      throw DiagnosticsError(
        syntax: node,
        message:
          """
          Cannot create variable declaration with argument for macro \
          @COWStorageAddProperty: \(arg.trimmed.debugDescription)
          """,
        id: .internalInconsistency
      )
    }
    
    return [descriptor.makeVarDecl()]
  }
  
}

public struct COWMakeStorageMacro: PeerMacro, NameLookupable {
  
  // MARK: - NameLookupable
  
  internal static var name: String {
    "COWMakeStorage"
  }
  
  // MARK: - PeerMacro
  
  public static func expansion<
    Context : MacroExpansionContext,
    Declaration : DeclSyntaxProtocol
  >(
    of node: AttributeSyntax,
    providingPeersOf declaration: Declaration,
    in context: Context
  ) throws -> [DeclSyntax] {
    guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
      throw DiagnosticsError(
        syntax: declaration,
        message:
          """
          @COWMakeStorage can only be applied on function declarations.
          """,
        id: .invalidType
      )
    }
    guard funcDecl.isStatic else {
      throw DiagnosticsError(
        syntax: declaration,
        message:
          """
          @COWMakeStorage can only be applied on static function \
          declarations.
          """,
        id: .invalidType
      )
    }
    return []
  }
  
}

// MARK: - @COWMacrosPlugin

@main
internal struct COWMacrosPlugin: CompilerPlugin {
  
  internal let providingMacros: [Macro.Type] = [
    COWMacro.self,
    COWIncludedMacro.self,
    COWExcludedMacro.self,
    COWStorageMacro.self,
    COWStorageAddPropertyMacro.self,
    COWMakeStorageMacro.self,
  ]
  
}
