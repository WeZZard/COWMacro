import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

@_implementationOnly import SwiftSyntaxBuilder
@_implementationOnly import SwiftDiagnostics

// MARK: - @COW

// TODO: Can use custom storage
public struct COWMacro:
  MemberMacro,
  MemberAttributeMacro,
  ConformanceMacro
{
  internal static let moduleName = "COW"
  
  internal static let macroName = "COW"
  
  internal static let includedMacroName = "COWIncluded"
  
  internal static let excludedMacroName = "COWExcluded"
  
  internal static let storageMacroName = "COWStorage"
  
  internal static let storagePropertyMacroName
    = "COWStorageProperty"
  
  internal static func makeUniqueStorageIfNeeded(
    _ storageName: TokenSyntax
  ) -> DeclSyntax {
    return
      """
      internal nonisolated mutating func _makeUniqueStorageIfNeeded() {
        guard !isKnownUniquelyReferenced(&\(storageName)) else {
          return
        }
        \(storageName) = .create(minimumCapacity: 1) { prototype in
          prototype.withUnsafeMutablePointerToHeader {
            $0.pointee = Void()
          }
          prototype.withUnsafeMutablePointerToElements { elements in
            \(storageName).withUnsafeMutablePointerToElements { oldElements in
              elements.pointee = oldElements.pointee
            }
          }
        }
      }
      """
  }
  
  internal struct CopyOnWritable {
    
    internal static let conformanceName = "CopyOnWritable"
    
    internal static var qualifiedConformanceName: String {
      return "\(moduleName).\(conformanceName)"
    }

    internal static var conformanceType: TypeSyntax {
      "\(raw: qualifiedConformanceName)"
    }
    
  }

  internal struct CopyOnWriteStorage {
    
    internal static let conformanceName = "CopyOnWriteStorage"
    
    internal static var qualifiedConformanceName: String {
      return "\(moduleName).\(conformanceName)"
    }

    internal static var conformanceType: TypeSyntax {
      "\(raw: qualifiedConformanceName)"
    }
    
  }
  
  internal static func transferredStorageMembers<Declaration: DeclGroupSyntax>(for declaration: Declaration) -> [VariableDeclSyntax] {
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
  ) -> StructDeclSyntax? {
    
    let allMemebers = transferredStorageMembers.map {
      MemberDeclListItemSyntax(decl: $0)
    }
    // TODO: + @COWStorage marked subtype'd memberd
    
    if allMemebers.isEmpty {
      return nil
    }
    
    return StructDeclSyntax(identifier: .identifier("Storage")) {
      MemberDeclListSyntax(allMemebers)
    }
  }
  
  internal static func storageMemberDecl(_ storageTypeName: TokenSyntax) -> (VariableDeclSyntax, IdentifierPatternSyntax) {
    let storageMemberName: IdentifierPatternSyntax = IdentifierPatternSyntax(identifier: .identifier("_$storage"))
    var varDecl = VariableDeclSyntax(Keyword.var, name: PatternSyntax(storageMemberName))
    var excludedAttr: AttributeSyntax = "@\(raw: excludedMacroName)"
    excludedAttr.trailingTrivia = .newlines(1)
    varDecl = varDecl.addAttribute(Syntax(excludedAttr))
    var identInitBindingPattern = PatternBindingSyntax(pattern: IdentifierPatternSyntax(identifier: "_$storage"))
    let initialization: ExprSyntax = """
    ManagedBuffer<Void, \(storageTypeName)>.create(minimumCapacity: 1) { prototype in
      prototype.withUnsafeMutablePointerToHeader {
        $0.pointee = Void()
      }
      prototype.withUnsafeMutablePointerToElements { storage in
        storage.pointee = \(storageTypeName)()
      }
    }
    """
    identInitBindingPattern.initializer = InitializerClauseSyntax(value: initialization)
    
    varDecl.bindings = PatternBindingListSyntax {
      identInitBindingPattern
    }
    
    return (varDecl, storageMemberName)
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
    
    // Create heap storage type
    let transferredStorageMembers = self.transferredStorageMembers(for: declaration)
    
    for property in transferredStorageMembers {
      // TODO: Fix with init accessor in the future
      if property.info?.hasStorage == false {
        throw DiagnosticsError(syntax: node, message: "@COW requires property '\(property.identifier?.text ?? "")' to have an initial value", id: .missingInitializer)
      }
    }
    
    guard let storageTypeDecl = self.storageTypeDecl(for: declaration, with: transferredStorageMembers, in: context) else {
      return []
    }
    
    let storageTypeName = TokenSyntax(storageTypeDecl.identifier.tokenKind, presence: storageTypeDecl.identifier.presence)
    
    // Create heap storage member
    let (storageMemberDecl, storageMemberName) = self.storageMemberDecl(storageTypeName)
    
    let makeUniqueStorageIfNeeded = self.makeUniqueStorageIfNeeded(storageMemberName.identifier)
    
    return [
      DeclSyntax(storageTypeDecl),
      DeclSyntax(storageMemberDecl),
      makeUniqueStorageIfNeeded,
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
        "@\(raw: includedMacroName)"
      ]
    }
    
    if varDecl.isValidCOWStorageProperty {
      return [
        "@\(raw: storagePropertyMacroName)"
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
        if inheritance.typeName.identifier == CopyOnWritable.conformanceName {
          return []
        }
      }
    }
    
    return [(CopyOnWritable.conformanceType, nil)]
  }
  
}

// MARK: - @COWIncluded

public struct COWIncludedMacro: AccessorMacro {
  
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
        return _$storage.withUnsafeMutablePointerToElements { elem in
          elem.pointee.\(identifier)
        }
      }
      """

    let setAccessor: AccessorDeclSyntax =
      """
      set {
        _makeUniqueStorageIfNeeded()
        _$storage.withUnsafeMutablePointerToElements { elem in
          elem.pointee.\(identifier) = newValue
        }
      }
      """
    
    return [
      getAccessor,
      setAccessor,
    ]
  }
  
}

// MARK: - @COWExcluded

public struct COWExcludedMacro: AccessorMacro {
  
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

public struct COWStorageMacro: ConformanceMacro {
  
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
        if inheritance.typeName.identifier == COWMacro.CopyOnWriteStorage.conformanceName {
          return []
        }
      }
    }
    
    return [(COWMacro.CopyOnWriteStorage.conformanceType, nil)]
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
