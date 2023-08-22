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
    
    let structDecl = try getStructDecl(from: declaration, attributedBy: node)
    
    let factory = COWExpansionFactory(
      node: node,
      context: context,
      appliedStructDecl: structDecl
    )
    
    if factory.diagnose() {
      return []
    }
    
    let userDefinedStorageTypeDecls = 
      structDecl.collectUserDefinedStorageTypeDecls()
    
    factory.setUserDefinedStorageTypeDecls(userDefinedStorageTypeDecls)
    
    if factory.diagnose() {
      return []
    }
    
    if !factory.hasUserStorage && !factory.hasAnyAdoptableProperties {
      return []
    }
    
    let storageTypeDecl = factory.getStorageTypeDecl()
    
    let storageName = structDecl.copyOnWriteStorageName ?? defaultStorageName
    
    // Create storage member
    let storageMemberDecl = factory.createStorageVarDecl(
      memberName: storageName,
      typeName: storageTypeDecl.typeName,
      hasDefaultInitializer: factory.hasDefaultInitializerInStorage
    )
    
    // Create explicit initializer if needed
    let explicitInitializerDecl = factory.createExplicitInitializerDeclIfNeeded(
      storageTypeDecl: storageTypeDecl,
      storageName: storageName
    )
    
    if factory.diagnose() {
      return []
    }
    
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
      
      guard varDecl.isNotExcludedAndStored else {
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
      
      let storedVarDecls = memberStructDecl.collectStoredVarDecls()
      var validAdoptableVarDecls = structDecl.collectAdoptableVarDecls()
        .filter(\.hasSingleBinding)
      
      // Get var decls in user storage type decl
      // Remove equivalents in include-able var decls
      
      for (index, eachVar) in validAdoptableVarDecls.enumerated().reversed() {
        for eachStoredVar in storedVarDecls {
          if eachVar.isEquivalent(to: eachStoredVar) {
            validAdoptableVarDecls.remove(at: index)
          }
        }
      }
      
      guard !validAdoptableVarDecls.isEmpty else {
        return []
      }
      
      let result = validAdoptableVarDecls.map { varDecl -> [AttributeSyntax] in
        varDecl.storagePropertyDescriptors.map { desc -> AttributeSyntax in
          AttributeSyntax(
            TypeSyntax(
              SimpleTypeIdentifierSyntax(
                name: .identifier(COWStorageAddPropertyMacro.name)
              )
            )
          ) {
            TupleExprElementSyntax(
              label: "keyword",
              expression: MemberAccessExprSyntax(name: desc.keyword.trimmed)
            )
            TupleExprElementSyntax(
              label: "name",
              expression: StringLiteralExprSyntax(content: desc.name.text)
            )
            if let type = desc.type {
              TupleExprElementSyntax(
                label: "type",
                expression: StringLiteralExprSyntax(
                  content: type.trimmedDescription
                )
              )
            }
            if let initializer = desc.initializer {
              TupleExprElementSyntax(
                label: "initialValue",
                expression: StringLiteralExprSyntax(
                  content: initializer.trimmedDescription
                )
              )
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
          varDecl.isNotExcludedAndStored,
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
