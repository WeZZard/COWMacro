import COW

@COW
struct Foo {

  var value: Int = 0
  
}

let foo = Foo()


@COW
struct Bar {
  
  @COWStorage
  struct Storage {
    
  }
  
  var foo: Int = 0
  
}
