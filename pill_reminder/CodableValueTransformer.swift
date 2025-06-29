//
//  CodableValueTransformer.swift
//  pill_reminder
//
//  Created by Akash Lakshmipathy on 15/06/25.
//

import Foundation

class CodableValueTransformer<T: Codable>: ValueTransformer {
    override class func transformedValueClass() -> AnyClass {
        return NSData.self
    }

    override class func allowsReverseTransformation() -> Bool {
        return true
    }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let typedValue = value as? T else { return nil }
        do {
            let data = try JSONEncoder().encode(typedValue)
            return data
        } catch {
            print("Encoding error: \(error)")
            return nil
        }
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("Decoding error: \(error)")
            return nil
        }
    }
}

@objc(DateArrayTransformer)
class DateArrayTransformer: CodableValueTransformer<[Date]> {}

@objc(StringArrayTransformer)
class StringArrayTransformer: CodableValueTransformer<[String]> {}
