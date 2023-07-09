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
  
  var value: Int = 0
  
}

@COW
struct Bar {
  
  var value: Int
  
}

final class COWTests: XCTestCase {
  
  func testCOWMakredStructRetainsValueSemantics() {
    var fee = Foo()
    let foe = fee
    let fum = fee
    
    XCTAssertEqual(fee.value, 0)
    XCTAssertEqual(foe.value, 0)
    XCTAssertEqual(fum.value, 0)
    
    fee.value = 1
    
    XCTAssertEqual(fee.value, 1)
    XCTAssertEqual(foe.value, 0)
    XCTAssertEqual(fum.value, 0)
  }
  
  func testCOWMakredStructRetainsValueSemantics2() {
    var fee = Bar(value: 0)
    let foe = fee
    let fum = fee
    
    XCTAssertEqual(fee.value, 0)
    XCTAssertEqual(foe.value, 0)
    XCTAssertEqual(fum.value, 0)
    
    fee.value = 1
    
    XCTAssertEqual(fee.value, 1)
    XCTAssertEqual(foe.value, 0)
    XCTAssertEqual(fum.value, 0)
  }
  
}
