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


struct Fee {

  var value: Int

  init(value: Int) {
    self.value = value
  }

  init(value2 value: Int) {
    self.value = value
  }

  init() {
    guard true else {
      self.init(value: 1)
      return
    }
    self.init(value2: 1)
  }

}
