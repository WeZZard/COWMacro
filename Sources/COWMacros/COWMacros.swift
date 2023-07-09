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
    guard let storageTypeDecl = try createOrUseExistedStorageTypeDecl(
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
    
    // Create make storage method if needed
    let makeStorageMethodDecl =
      try createOrUseExistedMakeStorageMethodDeclIfNeeded(
          for: structDecl,
          storageTypeDecl: storageTypeDecl,
          expandedBy: node,
          typeAnnoatedVarDecls: typeAnnoatedVarDecls
      )
    
    // Create explicit initializer if needed
    let explicitInitializerDecl = try createExplicitInitializerDeclIfNeeded(
      for: structDecl,
      expandedBy: node,
      makeStorageMethodDecl: makeStorageMethodDecl,
      storageTypeDecl: storageTypeDecl,
      storageName: storageName,
      typeAnnoatedVarDecls: typeAnnoatedVarDecls
    )
    
    var expansions = [DeclSyntax]()
    
    structDecl.addIfNeeded(storageTypeDecl, to: &expansions)
    structDecl.addIfNeeded(storageMemberDecl, to: &expansions)
    if let makeStorageMethodDecl {
      structDecl.addIfNeeded(makeStorageMethodDecl, to: &expansions)
    }
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
      
      for (index, eachIncludeable) in validIncludeableVarDecls.enumerated().reversed() {
        for eachStored in storedVarDecls {
          if eachIncludeable.isEquivalent(to: eachStored) {
            validIncludeableVarDecls.remove(at: index)
          }
        }
      }
      
      guard !validIncludeableVarDecls.isEmpty else {
        return []
      }
      
      return validIncludeableVarDecls.map { eachVarDecl -> [AttributeSyntax] in
        eachVarDecl.storagePropertyDescriptors.map { desc in
          return
            """
            @COWStorageAddProperty(
              keyword: .\(desc.keyword.trimmed),
              name: "\(desc.name.trimmed)",
              type: \(desc.type.map({"\"\($0.trimmed)\""}) ?? "nil"),
              initialValue: "\(desc.initializer.trimmed)"
            )
            """
        }
      }.flatMap({$0})
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
        message: "@COW applied on an non-identified decl syntax \(declaration). This should be considered as a bug in compiler of the COW macro compiler plugin.",
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
    return declaration.memberBlock.members.compactMap { eachItem in
      guard let varDecl = eachItem.decl.as(VariableDeclSyntax.self),
            varDecl.isIncludeable else {
        return nil
      }
      return varDecl
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
      return varDecl
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
    
    for invalidVarDecl in invalidVarDecls {
      throw DiagnosticsError(
        syntax: invalidVarDecl,
        message:
          """
          Decalring multiple properties over one variable is an undefined \
          behavior for the @COW macro.
          """,
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
  ) throws -> StructDeclSyntax? {
    let decl: StructDeclSyntax
    
    let userDefinedDecls = collectUserDefinedStorageTypeDecls(
      in: declaration
    )
    
    if userDefinedDecls.isEmpty {
      if initVarDecls.isEmpty && typeAnnoatedVarDecls.isEmpty {
        return nil
      }
      decl = self.createStorageTypeDecl(
        for: declaration,
        with: initVarDecls + typeAnnoatedVarDecls,
        in: context
      )
    } else if userDefinedDecls.count == 1 {
      decl = userDefinedDecls[0]
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
    return decl
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
      // FIXME: Remove the list syntax from the builder?
      InheritedTypeListSyntax([
        InheritedTypeSyntax(typeName: CopyOnWriteStorage.type)
      ])
    }
    let typeName = context.makeUniqueName("Storage")
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
  
  internal static func collecteUserDefinedStaticMakeStorageMethodDecls<
    Declaration: DeclGroupSyntax
  >(in declaration: Declaration) -> [FunctionDeclSyntax] {
    return declaration.memberBlock.members.compactMap { eachItem in
      guard let funcDecl = eachItem.decl.as(FunctionDeclSyntax.self),
            funcDecl.hasMacroApplication(COWMakeStorageMacro.name),
            funcDecl.isStatic else {
        return nil
      }
      
      return funcDecl
    }
  }
  
  internal static func diagnoseUnnecessaryUserDefinedMakeStorageMethod(
    storageTypeDecl: StructDeclSyntax,
    userDefinedMethodDecls: [FunctionDeclSyntax]
  ) throws {
    for eachMethodDecl in userDefinedMethodDecls {
      throw DiagnosticsError(
        syntax: eachMethodDecl,
        message:
          """
          @COW does not use this static make storage method because the \
          copy-on-write storage could be initialized without arguments.
          """,
        id: .undefinedBehavior,
        severity: .note
      )
    }
  }
  
  internal static func collectMakeStorageMethodParameters(
    node: AttributeSyntax,
    storageTypeDecl: StructDeclSyntax,
    typeAnnoatedVarDecls: [VariableDeclSyntax]
  ) throws -> [FunctionParameterSyntax] {
    let storageExplicitInitDecls = collectExplicitInitializers(
      on: storageTypeDecl
    )
    
    let parameters: [FunctionParameterSyntax]
    
    if storageExplicitInitDecls.isEmpty {
      parameters = typeAnnoatedVarDecls.compactMap {
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
    
    return parameters
  }
  
  internal static func createOrUseExistedMakeStorageMethodDeclIfNeeded<
    Declaration: DeclGroupSyntax
  >(
    for declaration: Declaration,
    storageTypeDecl: StructDeclSyntax,
    expandedBy node: AttributeSyntax,
    typeAnnoatedVarDecls: [VariableDeclSyntax]
  ) throws -> FunctionDeclSyntax? {
    
    let userDefinedMethodDecls =
      collecteUserDefinedStaticMakeStorageMethodDecls(in: storageTypeDecl)
    
    guard !typeAnnoatedVarDecls.isEmpty else {
      try diagnoseUnnecessaryUserDefinedMakeStorageMethod(
        storageTypeDecl: storageTypeDecl,
        userDefinedMethodDecls: userDefinedMethodDecls
      )
      return nil
    }
    
    guard userDefinedMethodDecls.isEmpty else {
      if userDefinedMethodDecls.count == 1 {
        return userDefinedMethodDecls[0]
      } else {
        throw DiagnosticsError(
          syntax: userDefinedMethodDecls[1],
          message:
            """
            @COW finds that there are multiple static make storage methods \
            defined. Only one definition is allowed.
            """,
          id: .undefinedBehavior
        )
      }
    }
    
    let parameters = try collectMakeStorageMethodParameters(
      node: node,
      storageTypeDecl: storageTypeDecl,
      typeAnnoatedVarDecls: typeAnnoatedVarDecls
    )
    
    // - Infer from type annotated variables / foward to the implicit
    //    initializer
    // - Forward to the unique explicit initializer
    // - Diagnose multiple explicit initializers were found on copy-on-write
    //    storage
    
    let storageTypeName = storageTypeDecl.typeName
    
    let funcDecl = try FunctionDeclSyntax(
      """
      static func _$makeStorage(\(FunctionParameterListSyntax(parameters))) -> \(storageTypeName)
      """
    ) {
      CodeBlockItemListSyntax {
        CodeBlockItemSyntax(item: .expr("return \(storageTypeName)("))
      }
      CodeBlockItemListSyntax(
        parameters.map { eachParam in
          CodeBlockItemSyntax(item: .expr(
            """
                \(eachParam.firstName): \(eachParam.secondName ?? eachParam.firstName)
            """
          ))
        }
      )
      CodeBlockItemListSyntax {
        CodeBlockItemSyntax(item: .expr(")"))
      }
    }
    
    return funcDecl
  }
  
  internal static func collectExplicitInitializers<
    Declaration: DeclGroupSyntax
  >(on declaration: Declaration) -> [InitializerDeclSyntax] {
    return declaration.memberBlock.members.compactMap { each in
      each.as(InitializerDeclSyntax.self)
    }
  }
  
  internal static func checkExplicitInitializers(
    _ initializers: [InitializerDeclSyntax]
  ) throws {
    
  }
  
  internal static func createExplicitInitializerDeclIfNeeded<
    Declaration: DeclGroupSyntax
  >(
    for declaration: Declaration,
    expandedBy node: AttributeSyntax,
    makeStorageMethodDecl: FunctionDeclSyntax?,
    storageTypeDecl: StructDeclSyntax,
    storageName: TokenSyntax,
    typeAnnoatedVarDecls: [VariableDeclSyntax]
  ) throws -> InitializerDeclSyntax? {
    guard let makeStorageMethodDecl else {
      return nil
    }
    
    guard !typeAnnoatedVarDecls.isEmpty else {
      return nil
    }
    
    let explicitInitializers = collectExplicitInitializers(on: declaration)
    
    guard explicitInitializers.isEmpty else {
      try checkExplicitInitializers(explicitInitializers)
      return nil
    }
    
    let parameters = try collectMakeStorageMethodParameters(
      node: node,
      storageTypeDecl: storageTypeDecl,
      typeAnnoatedVarDecls: typeAnnoatedVarDecls
    )
    
    let makeStorageName = makeStorageMethodDecl.identifier.trimmed
    
    let initDecl = try InitializerDeclSyntax("init(\(FunctionParameterListSyntax(parameters)))") {
      CodeBlockItemListSyntax {
        CodeBlockItemSyntax(item: .expr(
          """
          self.\(storageName) = Self.\(makeStorageName)(
          """
        ))
      }
      CodeBlockItemListSyntax(
        parameters.map { eachParam in
          CodeBlockItemSyntax(item: .expr(
            """
                \(eachParam.firstName): \(eachParam.secondName ?? eachParam.firstName)
            """
          ))
        }
      )
      CodeBlockItemListSyntax {
        CodeBlockItemSyntax(item: .expr(
          """
          )
          """
        ))
      }
    }
    
    return initDecl
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
        message: "The macro @COWIncluded shall have storage name get specified.",
        id: .internalInconsistency,
        severity: .error
      )
    }
    
    // TODO: Adopt init accessor in the future
    
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

public struct COWExcludedMacro: AccessorMacro, NameLookupable {
  
  // MARK: - NameLookupable
  
  internal static var name: String {
    "COWExcluded"
  }
  
  // MARK: - AccessorMacro
  
  public static func expansion<
    Context: MacroExpansionContext,
    Declaration: DeclSyntaxProtocol
  >(
    of node: AttributeSyntax,
    providingAccessorsOf declaration: Declaration,
    in context: Context
  ) throws -> [AccessorDeclSyntax] {
    // A marker only macro
    []
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
        message: "@COWStorageAddProperty can only be applied on @COWStorage marked struct types.",
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
        message: "Cannot create variable declaration with argument for macro @COWStorageAddProperty: \(arg.trimmed.debugDescription)",
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
