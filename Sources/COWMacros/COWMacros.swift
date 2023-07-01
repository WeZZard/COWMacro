import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

@_implementationOnly import SwiftSyntaxBuilder
@_implementationOnly import SwiftDiagnostics

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
  
  internal static func userDefinedStorageTypeDecls<Declaration: DeclGroupSyntax>(in declaration: Declaration) -> [StructDeclSyntax] {
    return declaration.memberBlock.members.compactMap { eachItem in
      guard let structDecl = eachItem.decl.as(StructDeclSyntax.self),
            structDecl.hasMacroApplication(COWStorageMacro.name) else {
        return nil
      }
      return structDecl
    }
  }
  
  internal static func collectValidVarDecls<Declaration: DeclGroupSyntax>(for declaration: Declaration) -> [VariableDeclSyntax] {
    return declaration.memberBlock.members.compactMap { eachItem in
      guard let varDecl = eachItem.decl.as(VariableDeclSyntax.self),
            varDecl.isValidForBeingIncludedInCOWStorage else {
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
    // TODO: + @COWStorage marked subtype'd memberd
    let inheritance = TypeInheritanceClauseSyntax {
      InheritedTypeListSyntax([InheritedTypeSyntax(typeName: CopyOnWriteStorage.type)])
    }
    return StructDeclSyntax(identifier: .identifier("Storage"), inheritanceClause: inheritance) {
      MemberDeclListSyntax(allMemebers)
    }
  }
  
  internal static func storageMemberDecl(memberName: TokenSyntax, typeName: TokenSyntax) -> DeclSyntax {
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
    guard let identified = declaration.asProtocol(IdentifiedDeclSyntax.self) else {
      return []
    }
    
    let storageMemberName = node.argument?.storageMemberName ?? "_$storage"
    
    let appliedType = identified.identifier
    
    if declaration.isEnum {
      throw DiagnosticsError(syntax: node, message: "@COW cannot be applied to enum type \(appliedType.text)", id: .invalidType)
    }
    if declaration.isClass {
      // enumerations cannot store properties
      throw DiagnosticsError(syntax: node, message: "@COW cannot be applied to class type \(appliedType.text)", id: .invalidType)
    }
    if declaration.isActor {
      // actors cannot yet be supported for their isolation
      throw DiagnosticsError(syntax: node, message: "@COW cannot be applied to actor type \(appliedType.text)", id: .invalidType)
    }
    if !declaration.isStruct {
      // Swift may introduce other keywords that is parallel to `enum`,
      // `class` and `actor` in the future.
      throw DiagnosticsError(syntax: node, message: "@COW cannot be applied to non-struct type \(appliedType.text)", id: .invalidType)
    }
    
    // Create storage type
    let validVarDecls = self.collectValidVarDecls(for: declaration)
    
    if validVarDecls.isEmpty {
      return []
    }
    
    for property in validVarDecls {
      // TODO: Fix with init accessor in the future
      if property.info?.hasStorage == false {
        throw DiagnosticsError(syntax: node, message: "@COW requires property '\(property.identifier?.text ?? "")' to have an initial value", id: .missingInitializer)
      }
    }
    
    let userStorageTypeDecls = userDefinedStorageTypeDecls(in: declaration)
    
    let storageTypeDecl: StructDeclSyntax
    
    if userStorageTypeDecls.isEmpty {
      storageTypeDecl = self.storageTypeDecl(for: declaration, with: validVarDecls, in: context)
    } else if userStorageTypeDecls.count == 1 {
      storageTypeDecl = userStorageTypeDecls[0]
    } else {
      let secondUserStorageTypeDecl = userStorageTypeDecls[1]
      throw DiagnosticsError(syntax: secondUserStorageTypeDecl, message: "Only one sub-struct can be marked with @COWStorage in a @COW marked struct.", id: .duplicateCOWStorages)
    }
    
    let storageTypeName = TokenSyntax(storageTypeDecl.identifier.tokenKind, presence: storageTypeDecl.identifier.presence)
    
    // Create storage member
    let storageMemberDecl = self.storageMemberDecl(memberName: storageMemberName, typeName: storageTypeName)
    
    return [
      DeclSyntax(storageTypeDecl),
      storageMemberDecl,
    ]
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
    
    if !declaration.isStruct {
      return []
    }
    
    // Marks non-`@COWExcluded` stored properties with `@COWIncldued`
    // Marks `@COWStorageProperty` stored properties with `@COWExcluded`
    
    guard let varDecl = member.as(VariableDeclSyntax.self) else {
      return []
    }
    
    if varDecl.isValidForBeingIncludedInCOWStorage {
      return [
        "@\(raw: COWIncludedMacro.name)"
      ]
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
    guard let property = declaration.as(VariableDeclSyntax.self),
          property.isValidForBeingIncludedInCOWStorage,
          let identifier = property.identifier else {
      return []
    }
    
    // TODO: initAccessor
    
    let getAccessor: AccessorDeclSyntax =
      """
      get {
        return _$storage.\(identifier)
      }
      """

    let setAccessor: AccessorDeclSyntax =
      """
      set {
        _$storage.\(identifier) = newValue
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
    // This macro is a mark only macro.
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

public struct COWStorageAddPropertyMacro: MemberMacro {
  
  public static func expansion<
    Declaration: DeclGroupSyntax,
    Context: MacroExpansionContext
  >(
    of node: AttributeSyntax,
    providingMembersOf declaration: Declaration,
    in context: Context
  ) throws -> [DeclSyntax] {
    []
  }
  
}

// MARK: - @COWStorageForwardedMacro

public struct COWStorageForwardedMacro: AccessorMacro {
  
  public static func expansion<
    Context: MacroExpansionContext,
    Declaration: DeclSyntaxProtocol
  >(
    of node: AttributeSyntax,
    providingAccessorsOf declaration: Declaration,
    in context: Context
  ) throws -> [AccessorDeclSyntax] {
    // TODO: Diagnose warn that code generation is forbidden if there is get/_read/unsafeAddressor or set/_modify/unsafeMutableAddressor
    // TODO: Diagnose error when the root type of the key-path does not conform to COW.CopyOnWriteStorage
    []
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
    COWStorageForwardedMacro.self,
  ]
  
}
