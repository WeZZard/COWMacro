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
  
  func testBoxProjectsItself() {
    struct Value: CopyOnWriteStorage, Equatable {
      
      var value: Int
      
    }
    
    @_Box
    var value: Value = Value(value: 0)
    
    XCTAssertTrue($value._buffer === _value._buffer)
    
  }
  
  func testBoxProjectedValueModifiesItself() {
    struct Value: CopyOnWriteStorage {
      
      var value: Int
      
    }
    
    @_Box
    var value1: Value = Value(value: 1)
    
    @_Box
    var value2: Value = Value(value: 2)
    
    XCTAssertTrue(_value1._buffer !== _value2._buffer)
    
    $value1 = $value2
    
    XCTAssertTrue(_value1._buffer === _value2._buffer)
    
  }
  
  func testBoxConformsToEquatableWhenTheContentsTypeConformsToEquatable() {
    struct Value: CopyOnWriteStorage, Equatable {
      
      var value: Int
      
    }
    
    @_Box
    var value1: Value = Value(value: 1)
    
    @_Box
    var value2: Value = Value(value: 1)
    
    XCTAssertEqual(_value1, _value2)
  }
  
  func testBoxConformsToHashableWhenTheContentsTypeConformsToHashable() {
    struct Value: CopyOnWriteStorage, Hashable {
      
      var value: Int
      
    }
    
    @_Box
    var value1: Value = Value(value: 1)
    
    @_Box
    var value2: Value = Value(value: 1)
    
    XCTAssertEqual(_value1.hashValue, _value2.hashValue)
  }
  
  func testBoxConformsToComparableWhenTheContentsTypeConformsToComparable() {
    struct Value: CopyOnWriteStorage, Comparable {
      
      var value: Int
      
      static func < (lhs: Value, rhs: Value) -> Bool {
        return lhs.value < rhs.value
      }
      
    }
    
    @_Box
    var value1: Value = Value(value: 1)
    
    @_Box
    var value2: Value = Value(value: 2)
    
    @_Box
    var value3: Value = Value(value: 3)
    
    XCTAssertTrue(_value1 < _value2)
    XCTAssertTrue(_value2 > _value1)
    
    XCTAssertTrue(_value1 == _value1)
    
    XCTAssertTrue(_value2 < _value3)
    XCTAssertTrue(_value3 > _value2)
  }
  
  func testBoxConformsToCodableWhenTheContentsTypeConformsToCodable() {
    struct Value: CopyOnWriteStorage, Codable, Equatable {
      
      var value: Int
      
    }
    
    do {
      
      @_Box
      var value1: Value = Value(value: 100)
      
      let encoder = JSONEncoder()
      
      let data = try encoder.encode(_value1)
      
      let decoder = JSONDecoder()
      
      let value2 = try decoder.decode(_Box<Value>.self, from: data)
     
      XCTAssertEqual(_value1, value2)
      
    } catch _ {
      XCTFail()
    }
    
  }
  
}
