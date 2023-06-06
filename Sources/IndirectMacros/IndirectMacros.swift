import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum CustomError: Error, CustomStringConvertible {
  case message(String)
  
  var description: String {
    switch self {
    case .message(let text):
      return text
    }
  }
}

private extension DeclSyntaxProtocol {
  
  var isIndirectableStoredProperty: Bool {
    guard let property = self.as(VariableDeclSyntax.self),
          let binding = property.bindings.first else {
      return false
    }
    
    return binding.accessor == nil
  }
  
  var typedStoredProperty: [(name: String, type: String)] {
    guard let property = self.as(VariableDeclSyntax.self) else {
      return []
    }
    
    let storedBindings = property.bindings.filter({$0.accessor == nil})
    
    let names: [(name: String, type: String)] = storedBindings.compactMap { binding -> (String, String)? in
      guard let identPattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
        return nil
      }
      let id: String = identPattern.identifier.text
      guard let type: String = binding.typeAnnotation?.type.description else {
        // No type annotation binding
        // Maybe: var foo = 0
        // TODO: Offer a property-wrapper-like rewriting behavior.
        return nil
      }
      return (name: id , type: type)
    }
    
    return names
  }
  
  var initializer: InitializerDeclSyntax? {
    guard let initializer = self.as(InitializerDeclSyntax.self) else {
      return nil
    }
    return initializer
  }
  
}

public struct IndirectMacro: MemberMacro, MemberAttributeMacro {
  
  // MARK: - MemberMacro
  public static func expansion<
    Declaration: DeclGroupSyntax,
    Context: MacroExpansionContext
  >(
    of node: AttributeSyntax,
    providingMembersOf declaration: Declaration,
    in context: Context
  ) throws -> [DeclSyntax] {
    guard declaration.asProtocol(IdentifiedDeclSyntax.self) != nil else {
      return []
    }
    
    let storedProperties = declaration.memberBlock.members.filter {
      $0.decl.isIndirectableStoredProperty
    }
    
    let initializers = declaration.memberBlock.members.compactMap({ item -> MemberDeclListItemSyntax? in
      guard let initializer = item.decl.initializer else {
        return nil
      }
      return MemberDeclListItemSyntax(initializer)
    })
    
    let memberList = MemberDeclListSyntax(
      storedProperties + initializers
    )
    
    let noInitializer = initializers.count == 0
    
    let valueTypeName = context.makeUniqueName("_Value")
    
    let boxTypeName = context.makeUniqueName("_Box")
    
    let boxedValue: DeclSyntax =
      """
      private struct \(valueTypeName) {
        \(memberList)
      }
      
      @propertyWrapper
      private class \(boxTypeName) {
        var wrappedValue: \(valueTypeName)
      
        init(wrappedValue: \(valueTypeName)) {
          self.wrappedValue = wrappedValue
        }
      }
      """
    
    let storage: DeclSyntax =
      """
      @\(boxTypeName)
      private var _storage: \(valueTypeName)
      """
    
    let makeUniqueBoxIfNeeded: DeclSyntax =
      """
      private mutating func _makeUniqueBoxIfNeeded() {
        if !isKnownUniquelyReferenced(&__storage) {
          __storage = \(boxTypeName)(wrappedValue: __storage.wrappedValue)
        }
      }
      """
    
    let wrappedInitializers = initializers.compactMap { item -> DeclSyntax? in
      guard var initializer = item.decl.initializer else {
        return nil
      }
      
      let names = initializer.signature.input.parameterList.map({(firstName: $0.firstName, secondName: $0.secondName ?? $0.firstName)})
      
      let body: DeclSyntax =
        """
        self._storage = \(valueTypeName)(\(raw: names.map({ "\($0.firstName): \($0.secondName)" }).joined(separator: ", "))
        """
      
      initializer.body = CodeBlockSyntax(body)
      
      return DeclSyntax(initializer)
    }
    
    let memberwiseInitializer: [DeclSyntax]
    
    if noInitializer {
      let storedProperties = declaration.memberBlock.members.flatMap({$0.decl.typedStoredProperty})
      
      memberwiseInitializer = [
        """
        init(\(raw: storedProperties.map({"\($0.name) : \($0.type)"}).joined(separator: ", "))) {
          self._storage = \(valueTypeName)(\(raw: storedProperties.map({"\($0.name) : \($0.name)"}).joined(separator: ", ")))
        }
        """
      ]
    } else {
      memberwiseInitializer = []
    }
    
    return [
      boxedValue,
      makeUniqueBoxIfNeeded,
      storage,
    ] + wrappedInitializers + memberwiseInitializer
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
    guard member.isIndirectableStoredProperty else {
      return []
    }
    
    return [
      AttributeSyntax(
        attributeName: SimpleTypeIdentifierSyntax(
          name: .identifier("IndirectProperty")
        )
      )
    ]
  }
  
}

public struct IndirectPropertyMacro: AccessorMacro {
  
  public static func expansion<
    Context: MacroExpansionContext,
    Declaration: DeclSyntaxProtocol
  >(
    of node: AttributeSyntax,
    providingAccessorsOf declaration: Declaration,
    in context: Context
  ) throws -> [AccessorDeclSyntax] {
    guard let property = declaration.as(VariableDeclSyntax.self),
          let binding = property.bindings.first,
          let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
          binding.accessor == nil
    else {
      return []
    }
    
    if identifier.text == "_storage" { return [] }
    
    let getAccessor: AccessorDeclSyntax =
      """
      get {
        return _storage.\(identifier)
      }
      """
    
    let setAccessor: AccessorDeclSyntax =
      """
      set {
        _makeUniqueBoxIfNeeded()
        _storage.\(identifier) = newValue
      }
      """
    
    return [getAccessor, setAccessor]
  }
  
}


@main
struct IndirectMacroPluginPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    IndirectMacro.self,
    IndirectPropertyMacro.self,
  ]
}
