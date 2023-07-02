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

internal struct CopyOnWritable: NameLookupable {
  
  internal static var name: String {
    "CopyOnWritable"
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
  ConformanceMacro,
  NameLookupable
{
  
  internal static func allUserDefinedStorageTypeDecls<
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
  
  internal static func collectStoredVarDecls<
    Declaration: DeclGroupSyntax
  >(on declaration: Declaration) -> [VariableDeclSyntax] {
    return declaration.memberBlock.members.compactMap { eachItem in
      guard let varDecl = eachItem.decl.as(VariableDeclSyntax.self),
            varDecl.info?.hasStorage == true else {
        return nil
      }
      return varDecl
    }
  }
  
  internal static func storageTypeDecl<
    Declaration: DeclGroupSyntax,
    Context: MacroExpansionContext
  >(
    for declaration: Declaration,
    with transferredStorageMembers: [VariableDeclSyntax],
    in context: Context
  ) -> StructDeclSyntax {
    let allMemebers = transferredStorageMembers.map {
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
  
  internal static func storageMemberDecl(
    memberName: TokenSyntax,
    typeName: TokenSyntax
  ) -> DeclSyntax {
    return
      """
      @\(raw: COWExcludedMacro.name)
      @\(_Box.type)
      var \(memberName): \(typeName) = \(typeName)()
      """
  }
  
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
    guard let identifiedDecl
            = declaration.asProtocol(IdentifiedDeclSyntax.self) else {
      return []
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
        message: "@COW cannot be applied to non-struct type \(appliedType.text)",
        id: .invalidType
      )
    }
    
    let storageName = structDecl.copyOnWriteStorageName ?? defaultStorageName
    
    // Create storage type
    let includeableVarDecls = self.collectIncludeableVarDecls(on: declaration)
    
    for property in includeableVarDecls {
      // TODO: Adopt changes brought by init accessor in the future
      if property.info?.hasStorage == false {
        throw DiagnosticsError(
          syntax: node,
          message: "@COW requires property '\(property.identifier?.text ?? "")' to have an initial value",
          id: .missingInitializer
        )
      }
    }
    
    let userStorageTypeDecls = allUserDefinedStorageTypeDecls(in: declaration)
    
    let storageTypeDecl: StructDeclSyntax
    
    if userStorageTypeDecls.isEmpty {
      if includeableVarDecls.isEmpty {
        return []
      }
      storageTypeDecl = self.storageTypeDecl(
        for: declaration,
        with: includeableVarDecls,
        in: context
      )
    } else if userStorageTypeDecls.count == 1 {
      storageTypeDecl = userStorageTypeDecls[0]
    } else {
      let secondUserStorageTypeDecl = userStorageTypeDecls[1]
      throw DiagnosticsError(
        syntax: secondUserStorageTypeDecl,
        message: "Only one subtyped struct can be marked with @COWStorage in a @COW marked struct.",
        id: .duplicateCOWStorages
      )
    }
    
    let storageTypeName = TokenSyntax(
      storageTypeDecl.identifier.tokenKind,
      presence: storageTypeDecl.identifier.presence
    )
    
    // Create storage member
    let storageMemberDecl = self.storageMemberDecl(
      memberName: storageName,
      typeName: storageTypeName
    )
    
    var expansions = [DeclSyntax]()
    
    declaration.addIfNeeded(DeclSyntax(storageTypeDecl), to: &expansions)
    declaration.addIfNeeded(storageMemberDecl, to: &expansions)
    
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
      
      let storedVarDecls = self.collectStoredVarDecls(on: memberStructDecl)
      var includeableVarDecls = self.collectIncludeableVarDecls(on: structDecl)
      
      // Get var decls in user storage type decl
      // Remove equivalents in include-able var decls
      
      for (index, eachIncludeable) in includeableVarDecls.enumerated().reversed() {
        for eachStored in storedVarDecls {
          if eachIncludeable.isEquivalent(to: eachStored) {
            includeableVarDecls.remove(at: index)
          }
        }
      }
      
      guard !includeableVarDecls.isEmpty else {
        return []
      }
      
      return includeableVarDecls.map { eachVarDecl -> [AttributeSyntax] in
        eachVarDecl.storagePropertyDescritors.map { eachInfo in
          return
            """
            @COWStorageAddProperty(
              keyword: .\(eachInfo.keyword.trimmed),
              name: "\(eachInfo.name.trimmed)",
              type: \(eachInfo.type.map({"\"\($0.trimmed)\""}) ?? "nil"),
              initialValue: "\(eachInfo.initializer.trimmed)"
            )
            """
        }
      }.flatMap({$0})
    }
    
    return []
  }
  
  // MARK: ConformanceMacro
  
  public static func expansion<
    Declaration: DeclGroupSyntax,
    Context: MacroExpansionContext
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
        if inheritance.typeName.identifier == CopyOnWritable.name {
          return []
        }
      }
    }
    
    return [(CopyOnWritable.type, nil)]
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
      throw DiagnosticsError(syntax: node, message: "The macro @COWIncluded shall have storage name get specified.", id: .internalInconsistency, severity: .error)
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

// MARK: - @COWForwardToStorage

public struct COWForwardToStorage: MemberAttributeMacro, NameLookupable {
  
  // MARK: - NameLookupable
  
  internal static var name: String {
    "COWForwardToStorage"
  }
  
  // MARK: - MemberAttributeMacro
  
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
    // This macro is mark only
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

public struct COWStorageAddPropertyMacro: MemberMacro {
  
  public static func expansion<
    Declaration: DeclGroupSyntax,
    Context: MacroExpansionContext
  >(
    of node: AttributeSyntax,
    providingMembersOf declaration: Declaration,
    in context: Context
  ) throws -> [DeclSyntax] {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      throw DiagnosticsError(syntax: node, message: "@COWStorageAddProperty can only be applied on struct types.", id: .invalidType)
    }
    
    guard structDecl.hasMacroApplication(COWStorageMacro.name) else {
      throw DiagnosticsError(syntax: node, message: "@COWStorageAddProperty can only be applied on @COWStorage marked struct types.", id: .requiresCOWStorage)
    }
    
    guard let arg = node.argument else {
      throw DiagnosticsError(syntax: node, message: "No argument found for macro @COWStorageAddProperty.", id: .internalInconsistency)
    }
    
    guard let descriptor = arg.storagePropertyDescriptor else {
      throw DiagnosticsError(syntax: node, message: "Cannot create variable declaration with argument for macro @COWStorageAddProperty: \(arg.trimmed.debugDescription)", id: .internalInconsistency)
    }
    
    return [descriptor.makeVarDecl()]
  }
  
}

// MARK: - @COWMacrosPlugin

@main
struct COWMacrosPlugin: CompilerPlugin {
  
  let providingMacros: [Macro.Type] = [
    COWMacro.self,
    COWIncludedMacro.self,
    COWExcludedMacro.self,
    COWStorageMacro.self,
    COWStorageAddPropertyMacro.self,
  ]
  
}
