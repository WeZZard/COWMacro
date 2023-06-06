
@attached(member, names: arbitrary)
@attached(memberAttribute)
public macro Indirect() =
  #externalMacro(module: "IndirectMacros", type: "IndirectMacro")

@attached(accessor)
public macro IndirectProperty() =
  #externalMacro(module: "IndirectMacros", type: "IndirectPropertyMacro")
