import IndirectMacroPlugin

@Indirect
struct Fee {
    
    var value: Int
    
}

let bar = Fee(value: 10)

@Indirect
struct Feo {
    
    var value = 0
    
}
