//
//  Metadata.swift
//  
//
//  Created by Sergej Jaskiewicz on 08/09/2019.
//

// The contents of this file is based on
// https://github.com/apple/swift/blob/master/include/swift/ABI/Metadata.h
// and must be up-to-date.

internal struct StructMetadataRef {

    private let metadataPtr: UnsafePointer<TargetStructMetadata>

    fileprivate init(_ type: Any.Type) {
        let metadataPtr = unsafeBitCast(type, to: UnsafeRawPointer.self)
        precondition(metadataKindIsStruct(metadataPtr), "\(type) is not a struct")
        self.metadataPtr = metadataPtr.bindMemory(to: TargetStructMetadata.self,
                                                  capacity: 1)
    }

    private var fieldCount: Int {
        return Int(metadataPtr.pointee.description.pointee.numFields)
    }

    private var fieldOffsets: UnsafeBufferPointer<Int32> {
        let fieldOffsetVectorOffset =
            Int(metadataPtr.pointee.description.pointee.fieldOffsetVectorOffset)

        if fieldOffsetVectorOffset == 0 {
            return UnsafeBufferPointer(start: nil, count: 0)
        }

        let start = UnsafeRawPointer(metadataPtr)
            .advanced(by: fieldOffsetVectorOffset * MemoryLayout<Int>.size)
            .bindMemory(to: Int32.self, capacity: fieldCount)

        return UnsafeBufferPointer(start: start, count: fieldCount)
    }
}

internal struct ClassMetadataRef {

    private let metadataPtr: UnsafePointer<TargetClassMetadata>

    fileprivate init(_ type: Any.Type) {
        let metadataPtr = unsafeBitCast(type, to: UnsafeRawPointer.self)
        precondition(metadataKindIsClass(metadataPtr), "\(type) is not a class")
        self.metadataPtr = metadataPtr.bindMemory(to: TargetClassMetadata.self,
                                                  capacity: 1)
    }
}

// MARK: - Private

// See https://github.com/apple/swift/blob/master/include/swift/Basic/RelativePointer.h
/// A direct relative reference to an object.
private struct RelativeDirectPointer<Pointee> {

    let offset: Int32

    func get() -> UnsafePointer<Pointee> {
        let offset = Int(self.offset)
        return withUnsafePointer(to: self) { p in
            UnsafeRawPointer(p)
                .advanced(by: offset)
                .bindMemory(to: Pointee.self, capacity: 1)
        }
    }

    var pointee: Pointee {
        get {
            assert(!isNull)
            return get().pointee
        }
    }

    var isNull: Bool {
        return offset == 0
    }
}

// MARK: Metadata

/// The structure of type metadata for structs.
private struct TargetStructMetadata {

    /// The kind. Only valid for non-class metadata.
    let kind: Int

    /// An out-of-line description of the type.
    let description: UnsafePointer<TargetStructDescriptor>
}

/// The structure of all class metadata.  This structure is embedded
/// directly within the class's heap metadata structure and therefore
/// cannot be extended without an ABI break.
///
/// Note that the layout of this type is compatible with the layout of
/// an Objective-C class.
private struct TargetClassMetadata {

    let objcISA: UnsafeRawPointer

    /// The metadata for the superclass. This is null for the root class.
    let superClass: UnsafePointer<TargetClassMetadata>?

    /// The cache data is used for certain dynamic lookups; it is owned
    /// by the runtime and generally needs to interoperate with
    /// Objective-C's use.
    let cacheData: (UnsafeRawPointer?, UnsafeRawPointer?)

    /// The data pointer is used for out-of-line metadata and is
    /// generally opaque, except that the compiler sets the low bit in
    /// order to indicate that this is a Swift metatype and therefore
    /// that the type metadata header is present.
    let data: UInt

    /// Swift-specific class flags.
    let classFlags: Int32

    /// The address point of instances of this type.
    let instanceAddressPoint: UInt32

    /// The required size of instances of this type.
    /// `instanceAddressPoint` bytes go before the address point;
    /// `instanceSize - instanceAddressPoint` bytes go after it.
    let instanceSize: UInt32

    /// The alignment mask of the address point of instances of this type.
    let instanceAlignmentMask: UInt16

    /// Reserved for runtime use.
    let reserved: UInt16

    /// The total size of the class object, including prefix and suffix
    /// extents.
    let classSize: UInt32

    /// The offset of the address point within the class object.
    let classAddressPoint: UInt32

    /// An out-of-line Swift-specific description of the type, or null
    /// if this is an artificial subclass.  We currently provide no
    /// supported mechanism for making a non-artificial subclass
    /// dynamically.
    let typeDescriptor: UnsafePointer<TargetClassDescriptor>?

    /// A function for destroying instance variables, used to clean up after an
    /// early return from a constructor. If null, no clean up will be performed
    /// and all ivars must be trivial.
    let ivarDestroyer: UnsafeRawPointer?
}

// MARK: Descriptors

private struct TargetStructDescriptor {

    // MARK: TargetContextDescriptor fields

    /// Flags describing the context, including its kind and format version.
    let flags: Int32

    /// The parent context, or null if this is a top-level context
    let parent: Int32

    // MARK: TargetTypeContextDescriptor fields

    /// The name of the type.
    let name: RelativeDirectPointer<CChar>

    /// A pointer to the metadata access function for this type.
    let accessFunctionPtr: RelativeDirectPointer<Int>

    /// A pointer to the field descriptor for the type, if any.
    let fieldDescriptor: RelativeDirectPointer<Int>

    // MARK: TargetValueTypeDescriptor

    // MARK: TargetStructDescriptor

    /// The number of stored properties in the struct.
    /// If there is a field offset vector, this is its length.
    let numFields: UInt32

    /// The offset of the field offset vector for this struct's stored
    /// properties in its metadata, if any. 0 means there is no field offset
    /// vector.
    let fieldOffsetVectorOffset: UInt32
}

private struct TargetClassDescriptor {

    // MARK: TargetContextDescriptor fields

    /// Flags describing the context, including its kind and format version.
    let flags: Int32

    /// The parent context, or null if this is a top-level context
    let parent: Int32

    // MARK: TargetTypeContextDescriptor fields

    /// The name of the type.
    let name: RelativeDirectPointer<CChar>

    /// A pointer to the metadata access function for this type.
    let accessFunctionPtr: RelativeDirectPointer<Int>

    /// A pointer to the field descriptor for the type, if any.
    let fieldDescriptor: RelativeDirectPointer<Int>

    // MARK: TargetClassDescriptor

    /// The type of the superclass, expressed as a mangled type name that can
    /// refer to the generic arguments of the subclass type.
    let superclassType: RelativeDirectPointer<CChar>

    /// If this descriptor does not have a resilient superclass, this is the
    /// negative size of metadata objects of this class (in words).
    let metadataNegativeSizeInWords: UInt32

    /// If this descriptor does not have a resilient superclass, this is the
    /// positive size of metadata objects of this class (in words).
    let metadataPositiveSizeInWords: UInt32

    /// The number of additional members added by this class to the class
    /// metadata.
    let numImmediateMembers: UInt32

    /// The number of stored properties in the class, not including its
    /// superclasses. If there is a field offset vector, this is its length.
    let numFields: UInt32

    /// The offset of the field offset vector for this class's stored
    /// properties in its metadata, in words. 0 means there is no field offset
    /// vector.
    ///
    /// If this class has a resilient superclass, this offset is relative to
    /// the size of the resilient superclass metadata. Otherwise, it is
    /// absolute.
    let fieldOffsetVectorOffset: UInt32
}

/// Field descriptors contain a collection of field records for a single
/// class, struct or enum declaration.
private struct FieldDescriptor {
    // https://github.com/apple/swift/blob/master/include/swift/Reflection/Records.h

    let mangledTypeName: RelativeDirectPointer<CChar>

    let superclass: RelativeDirectPointer<CChar>

    let kind: UInt16

    let fieldRecordSize: UInt16

    let numFields: UInt32

    var fields: UnsafeBufferPointer<FieldRecord> {
        return withUnsafePointer(to: self) {
            let start = UnsafeRawPointer($0.advanced(by: 1))
                .bindMemory(to: FieldRecord.self, capacity: Int(numFields))
            return UnsafeBufferPointer(start: start, count: Int(numFields))
        }
    }
}

private struct FieldRecord {

    let flags: UInt32

    var mangledTypeName: RelativeDirectPointer<CChar>

    var fieldName: RelativeDirectPointer<CChar>
}

private func metadataKindIsStruct(_ metadataPtr: UnsafeRawPointer) -> Bool {
    let metadataKindFlag = metadataPtr.load(as: Int.self)
    return metadataKindFlag == 1 ||
           metadataKindFlag == (0 | metadataKindIsNonHeapFlag)
}

private func metadataKindIsClass(_ metadataPtr: UnsafeRawPointer) -> Bool {
    let metadataKindFlag = metadataPtr.load(as: Int.self)
    return metadataKindFlag == 0 ||
           metadataKindFlag > metadataKindLastEnumerated
}

/// Non-heap metadata kinds have this bit set.
private let metadataKindIsNonHeapFlag = 0x200

/// The largest possible non-isa-pointer metadata kind value.
private let metadataKindLastEnumerated = 0x7FF
