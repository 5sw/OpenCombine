//
//  Locking.swift
//  
//
//  Created by Sergej Jaskiewicz on 11.06.2019.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#else
#error("How to do locking on this platform?")
#endif

@usableFromInline
internal final class Lock {

    @usableFromInline
    internal var _mutex = pthread_mutex_t()

    @inlinable @inline(__always)
    internal init(recursive: Bool) {
        var attrib = pthread_mutexattr_t()
        pthread_mutexattr_init(&attrib)
        if recursive {
            pthread_mutexattr_settype(&attrib, Int32(PTHREAD_MUTEX_RECURSIVE))
        }
        pthread_mutex_init(&_mutex, &attrib)
    }

    @inlinable @inline(__always)
    deinit {
        pthread_mutex_destroy(&_mutex)
    }

    @inlinable @inline(__always)
    internal func lock() {
        pthread_mutex_lock(&_mutex)
    }

    @inlinable @inline(__always)
    internal func unlock() {
        pthread_mutex_unlock(&_mutex)
    }

    @inlinable @inline(__always)
    internal func `do`<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}

extension Lock: CustomStringConvertible {
    @usableFromInline
    internal var description: String { return String(describing: _mutex) }
}

extension Lock: CustomReflectable {
    @usableFromInline
    internal var customMirror: Mirror { return Mirror(reflecting: _mutex) }
}

extension Lock: CustomPlaygroundDisplayConvertible {
    @usableFromInline
    internal var playgroundDescription: Any { return description }
}

internal struct UnsafeLock {

    private var mutex = pthread_mutex_t()

    internal init() {
        pthread_mutex_init(&mutex, nil)
    }

    @inline(__always)
    internal mutating func lock() {
        pthread_mutex_lock(&mutex)
    }

    @inline(__always)
    internal mutating func unlock() {
        pthread_mutex_unlock(&mutex)
    }

    internal mutating func destroy() {
        pthread_mutex_destroy(&mutex)
    }
}

internal struct UnsafeRecursiveLock {

    private var mutex = pthread_mutex_t()

    @inline(__always)
    internal init() {
        var attrib = pthread_mutexattr_t()
        pthread_mutexattr_init(&attrib)
        pthread_mutexattr_settype(&attrib, Int32(PTHREAD_MUTEX_RECURSIVE))
        pthread_mutex_init(&mutex, &attrib)
    }

    @inline(__always)
    internal mutating func lock() {
        pthread_mutex_lock(&mutex)
    }

    @inline(__always)
    internal mutating func unlock() {
        pthread_mutex_unlock(&mutex)
    }

    internal mutating func destroy() {
        pthread_mutex_destroy(&mutex)
    }
}
