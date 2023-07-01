//
//  COWTests.swift
//
//
//  Created by WeZZard on 7/1/23.
//

@_implementationOnly import XCTest

import COW

@COW
struct Foo {
  
  var bar: Int = 0
  
}

final class COWTests: XCTestCase {
  
  func testCOWMakredStructRetainsValueSemantics() {
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
  
}
