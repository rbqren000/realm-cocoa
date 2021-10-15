////////////////////////////////////////////////////////////////////////////
//
// Copyright 2021 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////
import Foundation
import Realm

/// Enum representing an option for `String` queries.
public struct StringOptions: OptionSet {
    /// :nodoc:
    public let rawValue: Int8
    /// :nodoc:
    public init(rawValue: Int8) {
        self.rawValue = rawValue
    }
    /// A case-insensitive search.
    public static let caseInsensitive = StringOptions(rawValue: 1)
    /// Query ignores diacritic marks.
    public static let diacriticInsensitive = StringOptions(rawValue: 2)
}

/**
 `Query` is a class used to create type-safe query predicates.

 With `Query` you are given the ability to create Swift style query expression that will then
 be constructed into an `NSPredicate`. The `Query` class should not be instantiated directly
 and should be only used as a paramater within a closure that takes a query expression as an argument.
 Example:
 ```swift
 public func where(_ query: ((Query<Element>) -> Query<Element>)) -> Results<Element>
 ```

 You would then use the above function like so:
 ```swift
 let results = realm.objects(Person.self).query {
    $0.name == "Foo" || $0.name == "Bar" && $0.age >= 21
 }
 ```

 ## Supported predicate types

 ### Prefix
 - NOT `!`
 ```swift
 let results = realm.objects(Person.self).query {
    !$0.dogsName.contains("Fido") || !$0.name.contains("Foo")
 }
 ```

 ### Comparisions
 - Equals `==`
 - Not Equals `!=`
 - Greater Than `>`
 - Less Than `<`
 - Greater Than or Equal `>=`
 - Less Than or Equal `<=`
 - Between `.contains(_ range:)`

 ### Collections
 - IN `.contains(_ element:)`
 - Between `.contains(_ range:)`
 - ANY ... IN `.containsAnyIn(_ collection:)`


 ### Map
 - @allKeys `.keys`
 - @allValues `.values`

 ### Compound
 - AND `&&`
 - OR `||`

 ### Collection Aggregation
 - @avg `.avg`
 - @min `.min`
 - @max `.max`
 - @sum `.sum`
 - @count `.count`
 ```swift
 let results = realm.objects(Person.self).query {
    !$0.dogs.age.avg >= 0 || !$0.dogsAgesArray.avg >= 0
 }
 ```

 ### Other
 - NOT `!`
 - Subquery `($0.fooList.intCol >= 5).count > n`

 */
@dynamicMemberLookup
public struct Query<T: _RealmSchemaDiscoverable> {
    /// This initaliser should be used from callers who require queries on primitive collections.
    /// - Parameter isPrimitive: True if performing a query on a primitive collection.
    public init(isPrimitive: Bool = false) {
        if isPrimitive {
            node = .keyPath(["self"], isCollection: true)
        } else {
            node = .keyPath([], isCollection: true)
        }
    }

    private let node: QueryNode

    private init(_ node: QueryNode) {
        self.node = node
    }

    private func appendKeyPath(_ keyPath: String, isCollection: Bool) -> QueryNode {
        if case let .keyPath(kp, c) = node {
            return .keyPath(kp + [keyPath], isCollection: c)
        } else if case let .mapSubscript(lhs, mapKeyPath, requiresNot) = node, case let .keyPath(kp, c) = mapKeyPath {
            return .mapSubscript(lhs, collectionKeyPath: .keyPath(kp + [keyPath], isCollection: c),
                                 requiresNot: requiresNot)
        }
        throwRealmException("Cannot apply a keypath to \(buildPredicate(node))")
    }

    private func extractCollectionName() -> QueryNode {
        if case let .keyPath(kp, isCollection) = node {
            if !kp.isEmpty {
                return .keyPath([kp[0]], isCollection: isCollection)
            }
        }
        throwRealmException("Cannot apply a keypath to \(buildPredicate(node))")
    }

    private func buildCollectionAggregateKeyPath(_ aggregate: String) -> QueryNode {
        if case let .keyPath(kp, isCollection) = node {
            var keyPaths = kp
            if keyPaths.count > 1 {
                keyPaths.insert(aggregate, at: 1)
            } else {
                keyPaths.append(aggregate)
            }
            return .keyPath(keyPaths, isCollection: isCollection)
        }
        throwRealmException("Cannot apply a keypath to \(buildPredicate(node))")
    }

    // MARK: Prefix

    /// :nodoc:
    public static prefix func ! (_ query: Query) -> Query {
        if case let .comparison(op, lhs, rhs, options: options) = query.node,
           case let .mapSubscript(mapLhs, mapName, _) = lhs {
            return Query(.comparison(operator: op, .mapSubscript(mapLhs, collectionKeyPath: mapName, requiresNot: true),
                                      rhs,
                                      options: options))
        } else {
            return Query(.not(query.node))
        }
    }

    // MARK: Comparable

    /// :nodoc:
    public static func == <V>(_ lhs: Query<V>, _ rhs: V) -> Query where V: _RealmSchemaDiscoverable {
        Query(.comparison(operator: .equal, lhs.node, .constant(rhs), options: []))
    }
    /// :nodoc:
    public static func == <U, V>(_ lhs: Query<U>, _ rhs: Query<V>) -> Query where U: _RealmSchemaDiscoverable, V: _RealmSchemaDiscoverable {
        Query(.comparison(operator: .equal, lhs.node, rhs.node, options: []))
    }
    /// :nodoc:
    public static func != <V>(_ lhs: Query<V>, _ rhs: V) -> Query where V: _RealmSchemaDiscoverable {
        Query(.comparison(operator: .notEqual, lhs.node, .constant(rhs), options: []))
    }
    /// :nodoc:
    public static func != <U, V>(_ lhs: Query<U>, _ rhs: Query<V>) -> Query where U: _RealmSchemaDiscoverable, V: _RealmSchemaDiscoverable {
        Query(.comparison(operator: .notEqual, lhs.node, rhs.node, options: []))
    }

    // MARK: Numerics

    /// :nodoc:
    public static func > <V>(_ lhs: Query<V>, _ rhs: V) -> Query where V: _QueryNumeric {
        Query(.comparison(operator: .greaterThan, lhs.node, .constant(rhs), options: []))
    }
    /// :nodoc:
    public static func > <U, V>(_ lhs: Query<U>, _ rhs: Query<V>) -> Query where U: _QueryNumeric, V: _QueryNumeric {
        Query(.comparison(operator: .greaterThan, lhs.node, rhs.node, options: []))
    }
    /// :nodoc:
    public static func >= <V>(_ lhs: Query<V>, _ rhs: V) -> Query where V: _QueryNumeric {
        Query(.comparison(operator: .greaterThanEqual, lhs.node, .constant(rhs), options: []))
    }
    /// :nodoc:
    public static func >= <U, V>(_ lhs: Query<U>, _ rhs: Query<V>) -> Query where U: _QueryNumeric, V: _QueryNumeric {
        Query(.comparison(operator: .greaterThanEqual, lhs.node, rhs.node, options: []))
    }
    /// :nodoc:
    public static func < <V>(_ lhs: Query<V>, _ rhs: V) -> Query where V: _QueryNumeric {
        Query(.comparison(operator: .lessThan, lhs.node, .constant(rhs), options: []))
    }
    /// :nodoc:
    public static func < <U, V>(_ lhs: Query<U>, _ rhs: Query<V>) -> Query where U: _QueryNumeric, V: _QueryNumeric {
        Query(.comparison(operator: .lessThan, lhs.node, rhs.node, options: []))
    }
    /// :nodoc:
    public static func <= <V>(_ lhs: Query<V>, _ rhs: V) -> Query where V: _QueryNumeric {
        Query(.comparison(operator: .lessThanEqual, lhs.node, .constant(rhs), options: []))
    }
    /// :nodoc:
    public static func <= <U, V>(_ lhs: Query<U>, _ rhs: Query<V>) -> Query where U: _QueryNumeric, V: _QueryNumeric {
        Query(.comparison(operator: .lessThanEqual, lhs.node, rhs.node, options: []))
    }

    // MARK: Compound

    /// :nodoc:
    public static func && (_ lhs: Query, _ rhs: Query) -> Query {
        Query(.comparison(operator: .and, lhs.node, rhs.node, options: []))
    }
    /// :nodoc:
    public static func || (_ lhs: Query, _ rhs: Query) -> Query {
        Query(.comparison(operator: .or, lhs.node, rhs.node, options: []))
    }

    // MARK: Subscript

    /// :nodoc:
    public subscript<V>(dynamicMember member: KeyPath<T, V>) -> Query<V> where T: ObjectBase {
        Query<V>(appendKeyPath(_name(for: member), isCollection: V.self is UntypedCollection))
    }
    /// :nodoc:
    public subscript<V: RealmCollectionBase>(dynamicMember member: KeyPath<T, V>) -> Query<V> where T: ObjectBase {
        Query<V>(appendKeyPath(_name(for: member), isCollection: true))
    }

    // MARK: Query Construction

    /// Constructs an NSPredicate compatibe string with its accompanying arguments.
    /// - Note: This is for internal use only and is exposed for testing purposes.
    public func _constructPredicate() -> (String, [Any]) {
        return buildPredicate(node)
    }

    /// Creates an NSPredicate compatibe string.
    /// - Returns: A tuple containing the predicate string and an array of arguments.

    /// Creates an NSPredicate from the query expression.
    internal var predicate: NSPredicate {
        let predicate = _constructPredicate()
        return NSPredicate(format: predicate.0, argumentArray: predicate.1)
    }
}

// MARK: OptionalProtocol

extension Query where T: OptionalProtocol {
    /// :nodoc:
    public subscript<V>(dynamicMember member: KeyPath<T.Wrapped, V>) -> Query<V> where T.Wrapped: ObjectBase {
        Query<V>(appendKeyPath(_name(for: member), isCollection: V.self is UntypedCollection))
    }
}

// MARK: RealmCollection

extension Query where T: RealmCollection {
    /// :nodoc:
    public subscript<V>(dynamicMember member: KeyPath<T.Element, V>) -> Query<V> where T.Element: ObjectBase {
        Query<V>(appendKeyPath(_name(for: member), isCollection: true))
    }

    /// Query the count of the objects in the collection.
    public var count: Query<Int> {
        Query<Int>(appendKeyPath("@count", isCollection: false))
    }
}

extension Query where T: RealmCollection {
    /// Checks if an element exists in this collection.
    public func contains<V>(_ value: T.Element) -> Query<V> {
        Query<V>(.comparison(operator: .in, .constant(value), node, options: []))
    }

    /// Checks if any elements contained in the given array are present in the collection.
    public func containsAny<U: Sequence, V>(in collection: U) -> Query<V> where U.Element == T.Element {
        Query<V>(.any(.comparison(operator: .in, node, .constant(collection), options: [])))
    }
}

extension Query where T: RealmCollection, T.Element: _QueryNumeric {
    /// Checks for all elements in this collection that are within a given range.
    public func contains<V>(_ range: Range<T.Element>) -> Query<V> {
        Query<V>(.comparison(operator: .and,
                             .comparison(operator: .greaterThanEqual, appendKeyPath("@min", isCollection: true), .constant(range.lowerBound), options: []),
                             .comparison(operator: .lessThan, appendKeyPath("@max", isCollection: true), .constant(range.upperBound), options: []), options: []))
    }

    /// Checks for all elements in this collection that are within a given range.
    public func contains<V>(_ range: ClosedRange<T.Element>) -> Query<V> {
        Query<V>(.comparison(operator: .and,
                             .comparison(operator: .greaterThanEqual, appendKeyPath("@min", isCollection: true), .constant(range.lowerBound), options: []),
                             .comparison(operator: .lessThanEqual, appendKeyPath("@max", isCollection: true), .constant(range.upperBound), options: []), options: []))
    }
}

extension Query where T: RealmCollection, T.Element: OptionalProtocol, T.Element.Wrapped: _QueryNumeric {
    /// Checks for all elements in this collection that are within a given range.
    public func contains<V>(_ range: Range<T.Element.Wrapped>) -> Query<V> {
        Query<V>(.comparison(operator: .and,
                             .comparison(operator: .greaterThanEqual, appendKeyPath("@min", isCollection: true), .constant(range.lowerBound), options: []),
                             .comparison(operator: .lessThan, appendKeyPath("@max", isCollection: true), .constant(range.upperBound), options: []), options: []))
    }

    /// Checks for all elements in this collection that are within a given range.
    public func contains<V>(_ range: ClosedRange<T.Element.Wrapped>) -> Query<V> {
        Query<V>(.comparison(operator: .and,
                             .comparison(operator: .greaterThanEqual, appendKeyPath("@min", isCollection: true), .constant(range.lowerBound), options: []),
                             .comparison(operator: .lessThanEqual, appendKeyPath("@max", isCollection: true), .constant(range.upperBound), options: []), options: []))
    }
}

extension Query where T: RealmCollection, T.Element: _QueryNumeric {
    /// :nodoc:
    public static func == <V>(_ lhs: Query<T>, _ rhs: T.Element) -> Query<V> {
        Query<V>(.comparison(operator: .equal, lhs.node, .constant(rhs), options: []))
    }

    /// :nodoc:
    public static func != <V>(_ lhs: Query<T>, _ rhs: T.Element) -> Query<V> {
        Query<V>(.comparison(operator: .notEqual, lhs.node, .constant(rhs), options: []))
    }

    /// :nodoc:
    public static func > <V>(_ lhs: Query<T>, _ rhs: T.Element) -> Query<V> {
        Query<V>(.comparison(operator: .greaterThan, lhs.node, .constant(rhs), options: []))
    }

    /// :nodoc:
    public static func >= <V>(_ lhs: Query<T>, _ rhs: T.Element) -> Query<V> {
        Query<V>(.comparison(operator: .greaterThanEqual, lhs.node, .constant(rhs), options: []))
    }

    /// :nodoc:
    public static func < <V>(_ lhs: Query<T>, _ rhs: T.Element) -> Query<V> {
        Query<V>(.comparison(operator: .lessThan, lhs.node, .constant(rhs), options: []))
    }

    /// :nodoc:
    public static func <= <V>(_ lhs: Query<T>, _ rhs: T.Element) -> Query<V> {
        Query<V>(.comparison(operator: .lessThanEqual, lhs.node, .constant(rhs), options: []))
    }
}

extension Query where T: RealmCollection,
                      T.Element: _QueryNumeric {
    /// Returns the minimum value in the collection.
    public var min: Query<T.Element> {
        Query<T.Element>(appendKeyPath("@min", isCollection: false))
    }

    /// Returns the maximum value in the collection.
    public var max: Query<T.Element> {
        Query<T.Element>(appendKeyPath("@max", isCollection: false))
    }

    /// Returns the average in the collection.
    public var avg: Query<T.Element> {
        Query<T.Element>(appendKeyPath("@avg", isCollection: false))
    }

    /// Returns the sum of all the values in the collection.
    public var sum: Query<T.Element> {
        Query<T.Element>(appendKeyPath("@sum", isCollection: false))
    }
}

// MARK: RealmKeyedCollection

extension Query where T: RealmKeyedCollection {
    /// Creates an expression that allows an equals comparison on a maps keys on the lhs, and on the rhs
    /// the ability to compare values in the map. e.g. `((mapString.@allKeys == %@) && NOT mapString CONTAINS %@)`
    private func mapSubscript<U>(_ member: T.Key) -> Query<U> where T.Key: _RealmSchemaDiscoverable {
        Query<U>(.mapSubscript(.comparison(operator: .equal, appendKeyPath("@allKeys", isCollection: true),
                                           .constant(member), options: []),
                               collectionKeyPath: extractCollectionName(),
                               requiresNot: false))
    }

    /// Checks if any elements contained in the given array are present in the map's values.
    public func containsAny<U: Sequence, V>(in collection: U) -> Query<V> where U.Element == T.Value {
        Query<V>(.any(.comparison(operator: .in, node, .constant(collection), options: [])))
    }
}

extension Query where T: RealmKeyedCollection, T.Key: _RealmSchemaDiscoverable {
    /// Checks if an element exists in this collection.
    public func contains<V>(_ value: T.Value) -> Query<V> {
        Query<V>(.comparison(operator: .in, .constant(value), node, options: []))
    }
    /// Allows a query over all values in the Map.
    public var values: Query<T.Value> {
        Query<T.Value>(appendKeyPath("@allValues", isCollection: false))
    }
    /// :nodoc:
    public subscript(member: T.Key) -> Query<T.Value> {
        return mapSubscript(member)
    }
}

extension Query where T: RealmKeyedCollection, T.Key: _RealmSchemaDiscoverable, T.Value: OptionalProtocol, T.Value.Wrapped: _RealmSchemaDiscoverable {
    /// Allows a query over all values in the Map.
    public var values: Query<T.Value.Wrapped> {
        Query<T.Value.Wrapped>(appendKeyPath("@allValues", isCollection: false))
    }
    /// :nodoc:
    public subscript(member: T.Key) -> Query<T.Value.Wrapped> {
        return mapSubscript(member)
    }
    /// :nodoc:
    public subscript(member: T.Key) -> Query<T.Value> where T.Value.Wrapped: ObjectBase {
        return mapSubscript(member)
    }
}

extension Query where T: RealmKeyedCollection, T.Key == String {
    /// Allows a query over all keys in the `Map`.
    public var keys: Query<String> {
        Query<String>(appendKeyPath("@allKeys", isCollection: false))
    }
}

extension Query where T: RealmKeyedCollection, T.Value: _QueryNumeric {
    /// Checks for all elements in this collection that are within a given range.
    public func contains<V>(_ range: Range<T.Value>) -> Query<V> {
        Query<V>(.comparison(operator: .and,
                             .comparison(operator: .greaterThanEqual, appendKeyPath("@min", isCollection: true), .constant(range.lowerBound), options: []),
                             .comparison(operator: .lessThan, appendKeyPath("@max", isCollection: true), .constant(range.upperBound), options: []), options: []))
    }

    /// Checks for all elements in this collection that are within a given range.
    public func contains<V>(_ range: ClosedRange<T.Value>) -> Query<V> {
        Query<V>(.comparison(operator: .and,
                             .comparison(operator: .greaterThanEqual, appendKeyPath("@min", isCollection: true), .constant(range.lowerBound), options: []),
                             .comparison(operator: .lessThanEqual, appendKeyPath("@max", isCollection: true), .constant(range.upperBound), options: []), options: []))
    }
}

extension Query where T: RealmKeyedCollection, T.Value: OptionalProtocol, T.Value.Wrapped: _QueryNumeric {
    /// Checks for all elements in this collection that are within a given range.
    public func contains<V>(_ range: Range<T.Value.Wrapped>) -> Query<V> {
        Query<V>(.comparison(operator: .and,
                             .comparison(operator: .greaterThanEqual, appendKeyPath("@min", isCollection: true), .constant(range.lowerBound), options: []),
                             .comparison(operator: .lessThan, appendKeyPath("@max", isCollection: true), .constant(range.upperBound), options: []), options: []))
    }

    /// Checks for all elements in this collection that are within a given range.
    public func contains<V>(_ range: ClosedRange<T.Value.Wrapped>) -> Query<V> {
        Query<V>(.comparison(operator: .and,
                             .comparison(operator: .greaterThanEqual, appendKeyPath("@min", isCollection: true), .constant(range.lowerBound), options: []),
                             .comparison(operator: .lessThanEqual, appendKeyPath("@max", isCollection: true), .constant(range.upperBound), options: []), options: []))
    }
}

extension Query where T: RealmKeyedCollection,
                      T.Key: _RealmSchemaDiscoverable,
                      T.Value: _QueryNumeric {
    /// Returns the minimum value in the keyed collection.
    public var min: Query<T.Value> {
        Query<T.Value>(appendKeyPath("@min", isCollection: false))
    }

    /// Returns the maximum value in the keyed collection.
    public var max: Query<T.Value> {
        Query<T.Value>(appendKeyPath("@max", isCollection: false))
    }

    /// Returns the average in the keyed collection.
    public var avg: Query<T.Value> {
        Query<T.Value>(appendKeyPath("@avg", isCollection: false))
    }

    /// Returns the sum of all the values in the keyed collection.
    public var sum: Query<T.Value> {
        Query<T.Value>(appendKeyPath("@sum", isCollection: false))
    }

    /// Returns the count of all the values in the keyed collection.
    public var count: Query<T.Value> {
        Query<T.Value>(appendKeyPath("@count", isCollection: false))
    }
}

// MARK: PersistableEnum

extension Query where T: PersistableEnum, T.RawValue: _RealmSchemaDiscoverable {
    /// :nodoc:
    public static func == <V>(_ lhs: Query<T>, _ rhs: T) -> Query<V> {
        Query<V>(.comparison(operator: .equal, lhs.node, .constant(rhs.rawValue), options: []))
    }
    /// :nodoc:
    public static func != <V>(_ lhs: Query<T>, _ rhs: T) -> Query<V> {
        Query<V>(.comparison(operator: .notEqual, lhs.node, .constant(rhs.rawValue), options: []))
    }
    /// :nodoc:
    public static func > <V>(_ lhs: Query<T>, _ rhs: T) -> Query<V> where T.RawValue: _QueryNumeric {
        Query<V>(.comparison(operator: .greaterThan, lhs.node, .constant(rhs.rawValue), options: []))
    }
    /// :nodoc:
    public static func > <U: PersistableEnum, V>(_ lhs: Query<T>, _ rhs: Query<U>) -> Query<V> where T.RawValue: _QueryNumeric, U.RawValue: _QueryNumeric {
        Query<V>(.comparison(operator: .greaterThan, lhs.node, rhs.node, options: []))
    }
    /// :nodoc:
    public static func >= <V>(_ lhs: Query<T>, _ rhs: T) -> Query<V> where T.RawValue: _QueryNumeric {
        Query<V>(.comparison(operator: .greaterThanEqual, lhs.node, .constant(rhs.rawValue), options: []))
    }
    /// :nodoc:
    public static func >= <U: PersistableEnum, V>(_ lhs: Query<T>, _ rhs: Query<U>) -> Query<V> where T.RawValue: _QueryNumeric, U.RawValue: _QueryNumeric {
        Query<V>(.comparison(operator: .greaterThanEqual, lhs.node, rhs.node, options: []))
    }
    /// :nodoc:
    public static func < <V>(_ lhs: Query<T>, _ rhs: T) -> Query<V> where T.RawValue: _QueryNumeric {
        Query<V>(.comparison(operator: .lessThan, lhs.node, .constant(rhs.rawValue), options: []))
    }
    /// :nodoc:
    public static func < <U: PersistableEnum, V>(_ lhs: Query<T>, _ rhs: Query<U>) -> Query<V> where T.RawValue: _QueryNumeric, U.RawValue: _QueryNumeric {
        Query<V>(.comparison(operator: .lessThan, lhs.node, rhs.node, options: []))
    }
    /// :nodoc:
    public static func <= <V>(_ lhs: Query<T>, _ rhs: T) -> Query<V> where T.RawValue: _QueryNumeric {
        Query<V>(.comparison(operator: .lessThanEqual, lhs.node, .constant(rhs.rawValue), options: []))
    }
    /// :nodoc:
    public static func <= <U: PersistableEnum, V>(_ lhs: Query<T>, _ rhs: Query<U>) -> Query<V> where T.RawValue: _QueryNumeric, U.RawValue: _QueryNumeric {
        Query<V>(.comparison(operator: .lessThanEqual, lhs.node, rhs.node, options: []))
    }
}

extension Query where T: PersistableEnum,
                      T.RawValue: _QueryNumeric {
    /// Returns the minimum value in the collection based on the keypath.
    public var min: Query {
        Query(buildCollectionAggregateKeyPath("@min"))
    }

    /// Returns the maximum value in the collection based on the keypath.
    public var max: Query {
        Query(buildCollectionAggregateKeyPath("@max"))
    }

    /// Returns the average in the collection based on the keypath.
    public var avg: Query {
        Query(buildCollectionAggregateKeyPath("@avg"))
    }

    /// Returns the sum of all the values in the collection based on the keypath.
    public var sum: Query {
        Query(buildCollectionAggregateKeyPath("@sum"))
    }

    /// Returns the count of all the values in the collection based on the keypath.
    public var count: Query {
        Query(buildCollectionAggregateKeyPath("@count"))
    }
}

// MARK: Optional

extension Query where T: OptionalProtocol,
                      T.Wrapped: PersistableEnum,
                      T.Wrapped.RawValue: _RealmSchemaDiscoverable {
    /// :nodoc:
    public static func == <V>(_ lhs: Query<T>, _ rhs: T) -> Query<V> {
        return Query<V>(.comparison(operator: .equal, lhs.node, lhs.enumValue(rhs), options: []))
    }
    /// :nodoc:
    public static func != <V>(_ lhs: Query<T>, _ rhs: T) -> Query<V> {
        return Query<V>(.comparison(operator: .notEqual, lhs.node, lhs.enumValue(rhs), options: []))
    }

    private func enumValue(_ rhs: T) -> QueryNode {
        if case Optional<Any>.none = rhs as Any {
            return .constant(nil)
        } else {
            return .constant(rhs._rlmInferWrappedType().rawValue)
        }
    }
}

extension Query where T: OptionalProtocol, T.Wrapped: PersistableEnum, T.Wrapped.RawValue: _QueryNumeric {
    /// :nodoc:
    public static func > <V>(_ lhs: Query<T>, _ rhs: T) -> Query<V> {
        Query<V>(.comparison(operator: .greaterThan, lhs.node, lhs.enumValue(rhs), options: []))
    }
    /// :nodoc:
    public static func >= <V>(_ lhs: Query<T>, _ rhs: T) -> Query<V> {
        Query<V>(.comparison(operator: .greaterThanEqual, lhs.node, lhs.enumValue(rhs), options: []))
    }
    /// :nodoc:
    public static func < <V>(_ lhs: Query<T>, _ rhs: T) -> Query<V> {
        Query<V>(.comparison(operator: .lessThan, lhs.node, lhs.enumValue(rhs), options: []))
    }
    /// :nodoc:
    public static func <= <V>(_ lhs: Query<T>, _ rhs: T) -> Query<V> {
        Query<V>(.comparison(operator: .lessThanEqual, lhs.node, lhs.enumValue(rhs), options: []))
    }
}

extension Query where T: OptionalProtocol,
                      T.Wrapped: PersistableEnum,
                      T.Wrapped.RawValue: _QueryNumeric {
    /// Returns the minimum value in the collection based on the keypath.
    public var min: Query {
        Query(buildCollectionAggregateKeyPath("@min"))
    }

    /// Returns the maximum value in the collection based on the keypath.
    public var max: Query {
        Query(buildCollectionAggregateKeyPath("@max"))
    }

    /// Returns the average in the collection based on the keypath.
    public var avg: Query {
        Query(buildCollectionAggregateKeyPath("@avg"))
    }

    /// Returns the sum of all the value in the collection based on the keypath.
    public var sum: Query {
        Query(buildCollectionAggregateKeyPath("@sum"))
    }
}

// MARK: _QueryNumeric

extension Query where T: _QueryNumeric {
    /// Checks for all elements in this collection that are within a given range.
    public func contains<V>(_ range: Range<T>) -> Query<V> {
        Query<V>(.comparison(operator: .and,
                             .comparison(operator: .greaterThanEqual, node, .constant(range.lowerBound), options: []),
                             .comparison(operator: .lessThan, node, .constant(range.upperBound), options: []), options: []))
    }

    /// Checks for all elements in this collection that are within a given range.
    public func contains<V>(_ range: ClosedRange<T>) -> Query<V> {
        Query<V>(.between(node,
                          lowerBound: .constant(range.lowerBound),
                          upperBound: .constant(range.upperBound)))
    }
}

// MARK: _QueryString

extension Query where T: _QueryString {
    /**
     Checks for all elements in this collection that equal the given value.
     `?` and `*` are allowed as wildcard characters, where `?` matches 1 character and `*` matches 0 or more characters.
     - parameter value: value used.
     - parameter caseInsensitive: `true` if it is a case-insensitive search.
     */
    public func like<V>(_ value: T, caseInsensitive: Bool = false) -> Query<V> {
        Query<V>(.comparison(operator: .like, node, .constant(value), options: caseInsensitive ? [.caseInsensitive] : []))
    }

    /**
     Checks for all elements in this collection that equal the given value.
     `?` and `*` are allowed as wildcard characters, where `?` matches 1 character and `*` matches 0 or more characters.
     - parameter value: value used.
     - parameter caseInsensitive: `true` if it is a case-insensitive search.
     */
    public func like<U, V>(_ column: Query<U>, caseInsensitive: Bool = false) -> Query<V> {
        Query<V>(.comparison(operator: .like, node, column.node, options: caseInsensitive ? [.caseInsensitive] : []))
    }
}

// MARK: _QueryBinary

extension Query where T: _QueryBinary {
    /**
     Checks for all elements in this collection that contains the given value.
     - parameter value: value used.
     - parameter options: A Set of options used to evaluate the search query.
     */
    public func contains<V>(_ value: T, options: StringOptions = []) -> Query<V> {
        Query<V>(.comparison(operator: .contains, node, .constant(value), options: options))
    }

    /**
     Compares that this column contains a value in another column.
     - parameter column: The other column.
     - parameter options: A Set of options used to evaluate the search query.
     */
    public func contains<U, V>(_ column: Query<U>, options: StringOptions = []) -> Query<V> where U: _QueryBinary {
        Query<V>(.comparison(operator: .contains, node, column.node, options: options))
    }

    /**
     Checks for all elements in this collection that starts with the given value.
     - parameter value: value used.
     - parameter options: A Set of options used to evaluate the search query.
     */
    public func starts<V>(with value: T, options: StringOptions = []) -> Query<V> {
        Query<V>(.comparison(operator: .beginsWith, node, .constant(value), options: options))
    }

    /**
     Compares that this column starts with a value in another column.
     - parameter column: The other column.
     - parameter options: A Set of options used to evaluate the search query.
     */
    public func starts<U, V>(with column: Query<U>, options: StringOptions = []) -> Query<V> {
        Query<V>(.comparison(operator: .beginsWith, node, column.node, options: options))
    }

    /**
     Checks for all elements in this collection that ends with the given value.
     - parameter value: value used.
     - parameter options: A Set of options used to evaluate the search query.
     */
    public func ends<V>(with value: T, options: StringOptions = []) -> Query<V> {
        Query<V>(.comparison(operator: .endsWith, node, .constant(value), options: options))
    }

    /**
     Compares that this column ends with a value in another column.
     - parameter column: The other column.
     - parameter options: A Set of options used to evaluate the search query.
     */
    public func ends<U, V>(with column: Query<U>, options: StringOptions = []) -> Query<V> {
        Query<V>(.comparison(operator: .endsWith, node, column.node, options: options))
    }

    /**
     Checks for all elements in this collection that equals the given value.
     - parameter value: value used.
     - parameter options: A Set of options used to evaluate the search query.
     */
    public func equals<V>(_ value: T, options: StringOptions = []) -> Query<V> {
        Query<V>(.comparison(operator: .equal, node, .constant(value), options: options))
    }

    /**
     Compares that this column is equal to the value in another given column.
     - parameter column: The other column.
     - parameter options: A Set of options used to evaluate the search query.
     */
    public func equals<U, V>(_ column: Query<U>, options: StringOptions = []) -> Query<V> {
        Query<V>(.comparison(operator: .equal, node, column.node, options: options))
    }

    /**
     Checks for all elements in this collection that are not equal to the given value.
     - parameter value: value used.
     - parameter options: A Set of options used to evaluate the search query.
     */
    public func notEquals<V>(_ value: T, options: StringOptions = []) -> Query<V> {
        Query<V>(.comparison(operator: .notEqual, node, .constant(value), options: options))
    }

    /**
     Compares that this column is not equal to the value in another given column.
     - parameter column: The other column.
     - parameter options: A Set of options used to evaluate the search query.
     */
    public func notEquals<U, V>(_ column: Query<U>, options: StringOptions = []) -> Query<V> {
        Query<V>(.comparison(operator: .notEqual, node, column.node, options: options))
    }
}

extension Query where T: OptionalProtocol, T.Wrapped: _QueryNumeric {
    /// Checks for all elements in this collection that are within a given range.
    public func contains<V>(_ range: Range<T.Wrapped>) -> Query<V> {
        Query<V>(.comparison(operator: .and,
                             .comparison(operator: .greaterThanEqual, node, .constant(range.lowerBound), options: []),
                             .comparison(operator: .lessThan, node, .constant(range.upperBound), options: []), options: []))
    }

    /// Checks for all elements in this collection that are within a given range.
    public func contains<V>(_ range: ClosedRange<T.Wrapped>) -> Query<V> {
        Query<V>(.between(node,
                          lowerBound: .constant(range.lowerBound),
                          upperBound: .constant(range.upperBound)))
    }
}

// MARK: Subquery

extension Query where T == Bool {
    /// Completes a subquery expression.
    /// - Usage:
    /// ```
    /// ($0.myCollection.age >= 21).count > 0
    /// ```
    /// - Note:
    /// Do not mix collections within a subquery expression. It is
    /// only permitted to reference a single collection per each subquery.
    public var count: Query<Int> {
        Query<Int>(.subqueryCount(node))
    }
}

// MARK: Keypath Collection Aggregates

/**
 You can use only use aggregates in numeric types as a keypath on a collection.
 ```swift
 let results = realm.objects(Person.self).query {
 !$0.dogs.age.avg >= 0
 }
 ```
 Where `dogs` is an array of objects.
 */
extension Query where T: _QueryNumeric {
    /// Returns the minimum value of the objects in the collection based on the keypath.
    public var min: Query {
        Query(buildCollectionAggregateKeyPath("@min"))
    }

    /// Returns the maximum value of the objects in the collection based on the keypath.
    public var max: Query {
        Query(buildCollectionAggregateKeyPath("@max"))
    }

    /// Returns the average of the objects in the collection based on the keypath.
    public var avg: Query {
        Query(buildCollectionAggregateKeyPath("@avg"))
    }

    /// Returns the sum of the objects in the collection based on the keypath.
    public var sum: Query {
        Query(buildCollectionAggregateKeyPath("@sum"))
    }
}

/// Tag protocol for all numeric types.
public protocol _QueryNumeric: _RealmSchemaDiscoverable { }
extension Int: _QueryNumeric { }
extension Int8: _QueryNumeric { }
extension Int16: _QueryNumeric { }
extension Int32: _QueryNumeric { }
extension Int64: _QueryNumeric { }
extension Float: _QueryNumeric { }
extension Double: _QueryNumeric { }
extension Decimal128: _QueryNumeric { }
extension Date: _QueryNumeric { }
extension AnyRealmValue: _QueryNumeric { }
extension Optional: _QueryNumeric where Wrapped: _QueryNumeric { }

/// Tag protocol for all types that are compatible with `String`.
public protocol _QueryString: _QueryBinary { }
extension String: _QueryString { }
extension Optional: _QueryString where Wrapped: _QueryString { }

/// Tag protocol for all types that are compatible with `Binary`.
public protocol _QueryBinary { }
extension Data: _QueryBinary { }
extension Optional: _QueryBinary where Wrapped: _QueryBinary { }

// MARK: QueryNode -

fileprivate indirect enum QueryNode {

    enum Operator: String {
        case or = "||"
        case and = "&&"
        case equal = "=="
        case notEqual = "!="
        case lessThan = "<"
        case lessThanEqual = "<="
        case greaterThan = ">"
        case greaterThanEqual = ">="
        case `in` = "IN"
        case contains = "CONTAINS"
        case beginsWith = "BEGINSWITH"
        case endsWith = "ENDSWITH"
        case like = "LIKE"
    }

    case any(_ child: QueryNode)
    case not(_ child: QueryNode)
    case constant(_ value: Any?)

    case keyPath(_ value: [String], isCollection: Bool)

    case comparison(operator: Operator, _ lhs: QueryNode, _ rhs: QueryNode, options: StringOptions)
    case between(_ lhs: QueryNode, lowerBound: QueryNode, upperBound: QueryNode)

    case subqueryCount(_ child: QueryNode)
    case mapSubscript(_ lhs: QueryNode, collectionKeyPath: QueryNode, requiresNot: Bool)
}

private func buildPredicate(_ root: QueryNode, subqueryCount: Int = 0) -> (String, [Any]) {
    let formatStr = NSMutableString()
    let arguments = NSMutableArray()
    var subqueryCounter = subqueryCount

    func buildExpression(_ lhs: QueryNode,
                         _ op: String,
                         _ rhs: QueryNode,
                         prefix: String? = nil) {
        formatStr.append("(")
        if let prefix = prefix {
            formatStr.append(prefix)
        }
        build(lhs)
        formatStr.append(" \(op) ")
        build(rhs)
        formatStr.append(")")
    }

    func buildCompoundExpression(_ lhs: QueryNode,
                                 _ op: String,
                                 _ rhs: QueryNode,
                                 prefix: String? = nil) {
        if let prefix = prefix {
            formatStr.append(prefix)
        }
        formatStr.append("(")
        build(lhs)
        formatStr.append(" \(op) ")
        build(rhs)
        formatStr.append(")")
    }

    func buildBetween(_ lowerBound: QueryNode, _ upperBound: QueryNode) {
        formatStr.append(" BETWEEN {")
        build(lowerBound)
        formatStr.append(", ")
        build(upperBound)
        formatStr.append("}")
    }

    func strOptions(_ options: StringOptions) -> String {
        if options == [] {
            return ""
        }
        return "[\(options.contains(.caseInsensitive) ? "c" : "")\(options.contains(.diacriticInsensitive) ? "d" : "")]"
    }

    func build(_ node: QueryNode, prefix: String? = nil) {
        func appendPrefix(_ str: String) -> String {
            if let prefix = prefix {
                return prefix + str
            }
            return str
        }
        switch node {
        case .any(let child):
            build(child, prefix: appendPrefix("ANY "))
        case .constant(let value):
            formatStr.append("%@")
            arguments.add(value ?? NSNull())
        case .keyPath(let kp, _):
            formatStr.append(kp.joined(separator: "."))
        case .not(let child):
            build(child, prefix: appendPrefix("NOT "))
        case .comparison(operator: let op, let lhs, let rhs, let options):
            switch op {
            case .and, .or:
                buildCompoundExpression(lhs, op.rawValue, rhs, prefix: prefix)
            default:
                buildExpression(lhs, "\(op.rawValue)\(strOptions(options))", rhs, prefix: prefix)
            }
        case .between(let lhs, let lowerBound, let upperBound):
            formatStr.append("(")
            build(lhs)
            buildBetween(lowerBound, upperBound)
            formatStr.append(")")
        case .subqueryCount(let inner):
            subqueryCounter += 1
            let (collectionName, node) = SubqueryRewriter.rewrite(inner, subqueryCounter)
            formatStr.append("SUBQUERY(\(collectionName), $col\(subqueryCounter), ")
            build(node)
            formatStr.append(").@count")
        case .mapSubscript(let lhs, let collectionKeyPath, let requiresNot):
            build(lhs)
            formatStr.append(" && ")
            if requiresNot {
                formatStr.append("NOT ")
            }
            build(collectionKeyPath)
        }
    }
    build(root)
    return (formatStr as String, (arguments as! [Any]))
}

private struct SubqueryRewriter {
    private var collectionName: String?
    private var counter: Int
    private mutating func rewrite(_ node: QueryNode) -> QueryNode {

        switch node {
        case .any(let child):
            return .any(rewrite(child))
        case .keyPath(let kp, let isCollection):
            if isCollection {
                precondition(kp.count > 0)
                collectionName = kp[0]
                var copy = kp
                copy[0] = "$col\(counter)"
                return .keyPath(copy, isCollection: isCollection)
            }
            return node
        case .not(let child):
            return .not(rewrite(child))
        case .comparison(operator: let op, let lhs, let rhs, options: let options):
            return .comparison(operator: op, rewrite(lhs), rewrite(rhs), options: options)
        case .between(let lhs, let lowerBound, let upperBound):
            return .between(rewrite(lhs), lowerBound: rewrite(lowerBound), upperBound: rewrite(upperBound))
        case .subqueryCount(let inner):
            return .subqueryCount(inner)
        case .constant:
            return node
        case .mapSubscript:
            throwRealmException("Subqueries do not support map subscripts.")
        }
    }

    static fileprivate func rewrite(_ node: QueryNode, _ counter: Int) -> (String, QueryNode) {
        var rewriter = SubqueryRewriter(counter: counter)
        let rewritten = rewriter.rewrite(node)
        guard let collectionName = rewriter.collectionName else {
            throwRealmException("Subquery must contain keypath starting with a collection")
        }
        return (collectionName, rewritten)
    }
}
