//
//  _BoxTests.swift
//
//
//  Created by WeZZard on 7/1/23.
//

@_implementationOnly import XCTest

import COW

final class _BoxTests: XCTestCase {
  
  func test_BoxValueSemanticBehavior() {
    struct Foo {
      
      var bar: Int {
        get {
          _$storage.bar
        }
        set {
          _$storage.bar = newValue
        }
      }
      
      struct Storage: CopyOnWriteStorage {
        
        var bar: Int = 0
        
      }
      
      @COW._Box
      var _$storage = Storage()
      
    }
    
    var fee = Foo()
    let foe = fee
    let fum = fee
    
    XCTAssertEqual(fee.bar, 0)
    XCTAssertEqual(foe.bar, 0)
    XCTAssertEqual(fum.bar, 0)
    
    fee.bar = 1
    
    XCTAssertEqual(fee.bar, 1)
    XCTAssertEqual(foe.bar, 0)
    XCTAssertEqual(fum.bar, 0)
    
  }
  
  func testBaselineValueSemanticBehavior() {
    var fee: Int = 0
    let foe = fee
    let fum = fee
    
    XCTAssertEqual(fee, 0)
    XCTAssertEqual(foe, 0)
    XCTAssertEqual(fum, 0)
    
    fee = 1
    
    XCTAssertEqual(fee, 1)
    XCTAssertEqual(foe, 0)
    XCTAssertEqual(fum, 0)
    
  }
  
}
