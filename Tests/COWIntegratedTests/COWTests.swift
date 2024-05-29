//
//  COWTests.swift
//
//
//  Created by WeZZard on 7/1/23.
//

@_implementationOnly import XCTest

import COW

final class COWTests: XCTestCase {
  
  @COW
  struct WithInitialValue {
    
    var value: Int = 0
    
  }
  
  func testWithInitialValue() {
    var fee = WithInitialValue()
    primitiveTestCRUD(&fee, properties: (\.value, 0, 100))
  }
  
  @COW
  struct WithInitialLetValue {
    
    let value: Int = 0
    
  }
  
  func testWithInitialLetValue() {
    var fee = WithInitialLetValue()
    primitiveTestCRUD(&fee, properties: (\.value, 0, 100))
  }
  
  @COW
  struct WithoutInitialValue {
    
    var value: Int
    
  }

  func testWithoutInitialValue() {
    var fee = WithoutInitialValue(value: 0)
    primitiveTestCRUD(&fee, properties: (\.value, 0, 100))
  }
  
  @COW
  struct WithoutInitialLetValue {
    
    var value: Int
    
  }

  func testWithoutInitialLetValue() {
    var fee = WithoutInitialLetValue(value: 0)
    primitiveTestCRUD(&fee, properties: (\.value, 0, 100))
  }
  
  @COW
  struct WithExplicitInitializer1 {
    
    var value: Int
    
    init(value: Int) {
      self._$storage = _$COWStorage(value: value)
      self.value = value
    }

  }
  
  func testWithExplicitInitializer1() {
    var fee = WithExplicitInitializer1(value: 0)
    primitiveTestCRUD(&fee, properties: (\.value, 0, 100))
  }
  
  // TODO: The following test case causes a compiler crash.
  /*
  @COW
  struct WithExplicitInitializerForLet1 {
    
    let value: Int
    
    init(value: Int) {
      self._$storage = _$COWStorage(value: value)
      self.value = value
    }

  }
  
  func testWithExplicitInitializerForLet1() {
    var fee = WithExplicitInitializerForLet1(value: 0)
    primitiveTestCRUD(&fee, properties: (\.value, 0, 100))
  }
   */
  
  @COW
  private struct WithExplicitInitializer2 {
    
    var value: Int
    
    init() {
      self._$storage = _$COWStorage(value: 0)
      self.value = value
    }

  }
  
  func testWithExplicitInitializer2() {
    var fee = WithExplicitInitializer2()
    primitiveTestCRUD(&fee, properties: (\.value, 0, 100))
  }
  
  @COW
  private struct WithExplicitInitializerForLet2 {
    
    var value: Int
    
    init() {
      self._$storage = _$COWStorage(value: 0)
      self.value = value
    }

  }
  
  func testWithExplicitInitializerForLet2() {
    var fee = WithExplicitInitializerForLet2()
    primitiveTestCRUD(&fee, properties: (\.value, 0, 100))
  }
  
  @COW
  struct WithStorageSingleVarType {
    
    @COWStorage
    struct Storage {
      
    }
    
    var value: Int
    
    init(value: Int) {
      self._$storage = Storage(value: value)
      self.value = value
    }

  }
  
  func testWithStorageSingleVarType() {
    var fee = WithStorageSingleVarType(value: 0)
    primitiveTestCRUD(&fee, properties: (\.value, 0, 100))
  }
  
  // TODO: The following test case causes a compiler crash.
  /*
  @COW
  struct WithStorageSingleLetType {
    
    @COWStorage
    struct Storage {
      
    }
    
    let value: Int
    
    init(value: Int) {
      self._$storage = Storage(value: value)
      self.value = value
    }

  }
  
  func testWithStorageSingleLetType() {
    var fee = WithStorageSingleLetType(value: 0)
    primitiveTestCRUD(&fee, properties: (\.value, 0, 100))
  }
   */
   
  @COW
  struct WithStorageMultipleVarType {
    
    @COWStorage
    struct Storage {
      
    }

    var value: Int
    
    var foo: Int
    
    init(foo: Int, value: Int) {
      self._$storage = Storage(value: value, foo: foo)
      self.value = value
    }

  }
  
  func testWithStorageMultipleVarType() {
    var fee = WithStorageMultipleVarType(foo: 2, value: 3)
    primitiveTestCRUD(&fee, properties: (\.foo, 2, 100), (\.value, 3, 50))
  }
  
  @COW
  struct WithStorageVarAndLetType {
    
    @COWStorage
    struct Storage {
      
    }

    var value: Int
    
    let foo: Int
    
    init(foo: Int, value: Int) {
      self._$storage = Storage(value: value, foo: foo)
      self.value = value
    }

  }
  
  func testWithStorageVarAndLetType() {
    var fee = WithStorageVarAndLetType(foo: 2, value: 3)
    primitiveTestCRUD(&fee, properties: (\.foo, 2, 100), (\.value, 3, 50))
  }
  
  @COW
  struct WithStorageMultipleVarTypeOnePropertyExcluded {
    
    @COWStorage
    struct Storage {
      
      var value: Int
      
    }
    
    @COWExcluded
    var value: Int {
      get {
        _$storage.value
      }
      set {
        _$storage.value = newValue
      }
    }
    
    var foo: Int
    
    init(foo: Int, value: Int) {
      self._$storage = Storage(value: value, foo: foo)
      self.value = value
    }
    
  }
  
  func testWithStorageMultipleVarTypeOnePropertyExcluded() {
    var fee = WithStorageMultipleVarTypeOnePropertyExcluded(foo: 2, value: 3)
    primitiveTestCRUD(&fee, properties: (\.foo, 2, 100), (\.value, 3, 50))
  }
  
  @COW
  struct WithStorageDefaultInitMultipleVarTypeOnePropertyExcluded {
    
    @COWStorage
    struct Storage {
      
      var value: Int
      
      init() {
        self.value = 0
        self.foo = 100
      }
      
    }
    
    @COWExcluded
    var value: Int {
      get {
        _$storage.value
      }
      set {
        _$storage.value = newValue
      }
    }
    
    var foo: Int
    
    init() {
      self._$storage = Storage()
      self.value = value
    }
    
  }
  
  func testWithStorageDefaultInitMultipleVarTypeOnePropertyExcluded() {
    var fee = WithStorageDefaultInitMultipleVarTypeOnePropertyExcluded()
    primitiveTestCRUD(&fee, properties: (\.foo, 100, 50), (\.value, 0, 50))
  }
  
  @COW
  struct EquatableStruct: Equatable {
    
    var value: Int = 0
    
  }
  
  func testEquatableStruct() {
    var fee = EquatableStruct()
    let foe = fee
    XCTAssertEqual(fee, foe)
    fee.value = 100
    XCTAssertNotEqual(fee, foe)
    fee.value = 0
    XCTAssertEqual(fee, foe)
  }
  
  struct NotConformingToHashable {}
  
  @COW
  struct ManuallyConformedEquatableStruct: Hashable {
    
    var value: Int = 0
    var wrappedValue: Int { value }
    let foo = NotConformingToHashable()
    
    func hash(into hasher: inout Hasher) {
      hasher.combine(value)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
      return lhs.wrappedValue == rhs.wrappedValue
    }
    
  }
  
  func testManuallyConformedEquatableStruct() {
    var fee = ManuallyConformedEquatableStruct()
    let foe = fee
    XCTAssertEqual(fee, foe)
    fee.value = 100
    XCTAssertNotEqual(fee, foe)
    fee.value = 0
    XCTAssertEqual(fee, foe)
  }
  
  // The only difference between this test case and
  // `ManuallyConformedEquatableStruct` is that `foo` is `@COWExcluded`.
  // This test fails to compile with previous implementation of `==`
  // workaround.
  @COW
  struct ManuallyConformedEquatableStruct2: Hashable {
    
    var value: Int = 0
    var wrappedValue: Int { value }
    
    @COWExcluded
    let foo = NotConformingToHashable()
    
    func hash(into hasher: inout Hasher) {
      hasher.combine(value)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
      return lhs.wrappedValue == rhs.wrappedValue
    }
    
  }
  
  func testManuallyConformedEquatableStruct2() {
    var fee = ManuallyConformedEquatableStruct2()
    let foe = fee
    XCTAssertEqual(fee, foe)
    fee.value = 100
    XCTAssertNotEqual(fee, foe)
    fee.value = 0
    XCTAssertEqual(fee, foe)
  }

  @COW
  struct ManuallyConformedEquatableStructWithCustomStorage: Hashable {
    
    @COWStorage
    struct CustomStorage {
      
    }
    
    var value: Int = 0
    var wrappedValue: Int { value }
    
    func hash(into hasher: inout Hasher) {
      hasher.combine(value)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
      return lhs.wrappedValue == rhs.wrappedValue
    }
    
  }
  
  func testManuallyConformedEquatableStructWithCustomStorage() {
    var fee = ManuallyConformedEquatableStructWithCustomStorage()
    let foe = fee
    XCTAssertEqual(fee, foe)
    fee.value = 100
    XCTAssertNotEqual(fee, foe)
    fee.value = 0
    XCTAssertEqual(fee, foe)
  }
  
  @COW
  struct CodableStruct: Codable {
    
    var value: Int = 0
    
  }
  
  func testCodableStruct() {
    var fee = CodableStruct()
    primitiveTestCRUD(&fee, properties: (\.value, 0, 100))
    do {
      let encoder = JSONEncoder()
      let data = try encoder.encode(fee)
      let decoder = JSONDecoder()
      let codededFee = try decoder.decode(CodableStruct.self, from: data)
      XCTAssertEqual(fee.value, codededFee.value)
    } catch _ {
      XCTFail()
    }
  }
  
  @COW
  struct CodableStructWithCodingKeys: Codable {
    
    var foo: Int = 0
    var bar: Int = 1
    
    init() {}
    
    enum CodingKeys: String, CodingKey {
      case foo = "FOO"
    }
  }
  
  func testCodableStructWithCodingKeys() {
    var foo = CodableStructWithCodingKeys()
    foo.foo = 2
    foo.bar = 3
    do {
      let encoder = JSONEncoder()
      let data = try encoder.encode(foo)
      let decoder = JSONDecoder()
      let bar = try decoder.decode(CodableStructWithCodingKeys.self, from: data)
      XCTAssertEqual(foo.foo, bar.foo)
      XCTAssertEqual(bar.bar, 1)
      let dict = try decoder.decode([String: Int].self, from: data)
      XCTAssertEqual(dict["FOO"], bar.foo)
    } catch _ {
      XCTFail()
    }
  }
  
  @COW
  struct CodableStructWithCustomStorageType: Codable {
    
    @COWStorage
    struct CustomStorage: Codable {
      
    }
    
    var value: Int = 0
    
  }
  
  func testCodableStructWithCustomStorageType() {
    var fee = CodableStructWithCustomStorageType()
    primitiveTestCRUD(&fee, properties: (\.value, 0, 100))
    do {
      let encoder = JSONEncoder()
      let data = try encoder.encode(fee)
      let decoder = JSONDecoder()
      let codededFee = try decoder.decode(CodableStruct.self, from: data)
      XCTAssertEqual(fee.value, codededFee.value)
    } catch _ {
      XCTFail()
    }
  }
  
  @COW
  struct HashableStruct: Hashable {
    
    var value: Int = 0
    
  }
  
  func testHashableStruct() {
    var fee = HashableStruct()
    primitiveTestCRUD(&fee, properties: (\.value, 0, 100))
    XCTAssertEqual(fee.hashValue, fee.hashValue)
  }
  
  // MARK: Utilities
  
  private func primitiveTestCRUD<T, FirstMember, each Member>(
    file: StaticString = #file,
    line: UInt = #line,
    _ instance: inout T,
    properties firstProperty: Property<T, FirstMember>,
    _ properties: repeat Property<T, each Member>
  ) where FirstMember: Equatable,
          repeat each Member: Equatable
  {
    COWBehaviorTester(file: file, line: line).test(on: &instance, for: firstProperty)
    repeat COWBehaviorTester(file: file, line: line).test(on: &instance, for: each properties)
  }
  
}

private typealias Property<Instance, Member> = (
  keyPath: KeyPath<Instance, Member>,
  initialValue: Member,
  updatedValue: Member
)

private struct COWBehaviorTester: ~Copyable {
  
  let file: StaticString
  
  let line: UInt
  
  init(file: StaticString, line: UInt) {
    self.file = file
    self.line = line
  }
  
  func test<Instance, Member: Equatable>(
    on instance: inout Instance,
    for property: Property<Instance, Member>
  ) {
    let (keyPath, initialValue, updatedValue) = property
    let oldValue = instance[keyPath: keyPath]
    
    XCTAssertEqual(
      oldValue,
      initialValue,
      "Comparing initial value failed for \(keyPath) \(oldValue) != \(initialValue)",
      file: file,
      line: line
    )
    
    let copiedInstance = instance
    
    if let keyPath = keyPath as? WritableKeyPath<Instance, Member> {
      instance[keyPath: keyPath] = updatedValue
      
      XCTAssertEqual(
        copiedInstance[keyPath: keyPath],
        oldValue,
        "Comparing copied initial value failed for \(keyPath) \(copiedInstance[keyPath: keyPath]) != \(oldValue)",
        file: file,
        line: line
      )
      XCTAssertEqual(
        instance[keyPath: keyPath],
        updatedValue,
        "Comparing updated value failed for \(keyPath) \(instance[keyPath: keyPath]) != \(updatedValue)",
        file: file,
        line: line
      )
    }
  }
  
}
