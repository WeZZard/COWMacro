//
//  PerformanceBenchmark.swift
//
//
//  Created by WeZZard on 8/22/23.
//

@_implementationOnly import XCTest

import COW

@COW
private struct COWStruct {
  
  var value1: Int = 0
  var value2: String = ""
  var value3: [String] = []
  var value4: [String : Any] = [:]
  
  var value5: Int = 0
  var value6: String = ""
  var value7: [String] = []
  var value8: [String : Any] = [:]
  
  var value9: Int = 0
  var value10: String = ""
  var value11: [String] = []
  var value12: [String : Any] = [:]
  
}

private struct NonCOWStruct {
  
  var value1: Int = 0
  var value2: String = ""
  var value3: [String] = []
  var value4: [String : Any] = [:]
  
  var value5: Int = 0
  var value6: String = ""
  var value7: [String] = []
  var value8: [String : Any] = [:]
  
  var value9: Int = 0
  var value10: String = ""
  var value11: [String] = []
  var value12: [String : Any] = [:]
  
}

private typealias Data = (Int, String, [String], [String : Any])

private var data: [Data] = (0..<1000).map { index -> Data in
  return (index, "\(index)", ["\(index)"], ["\(index)" : index])
}

final class PerformanceBenchmark: XCTestCase {
  
  func testCOWStructCopyPerformance() {
    let objective = COWStruct()
    var copied = [COWStruct]()
    let count = 100000
    copied.reserveCapacity(count)
    measure {
      for _ in 0..<count {
        copied.append(objective)
      }
    }
    sink(copied)
  }
  
  func testNonCOWStructCopyPerformance() {
    let objective = NonCOWStruct()
    var copied = [NonCOWStruct]()
    let count = 100000
    copied.reserveCapacity(count)
    measure {
      for _ in 0..<100000 {
        copied.append(objective)
      }
    }
    sink(copied)
  }
  
  func testCOWStructReadPerformance() {
    let objective = COWStruct()
    measure {
      for _ in 0..<1000000 {
        sink(objective.value1)
        sink(objective.value2)
        sink(objective.value3)
        sink(objective.value4)
      }
    }
  }
  
  func testNonCOWStructReadPerformance() {
    let objective = NonCOWStruct()
    measure {
      for _ in 0..<1000000 {
        sink(objective.value1)
        sink(objective.value2)
        sink(objective.value3)
        sink(objective.value4)
      }
    }
  }
  
  func testCOWStructWritePerformance() {
    var objective = COWStruct()
    measure {
      for _ in 0..<100 {
        for values in data {
          objective.value1 = values.0
          objective.value2 = values.1
          objective.value3 = values.2
          objective.value4 = values.3
        }
      }
    }
  }
  
  func testNonCOWStructWritePerformance() {
    var objective = NonCOWStruct()
    measure {
      for _ in 0..<100 {
        for values in data {
          objective.value1 = values.0
          objective.value2 = values.1
          objective.value3 = values.2
          objective.value4 = values.3
        }
      }
    }
  }
  
}

@inline(never)
private func sink(_ any: Any) {
  
}
