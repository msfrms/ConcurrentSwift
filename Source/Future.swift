//
// Created by Radaev Mikhail on 22.01.2018.
// Copyright (c) 2018 Radaev Mikhail. All rights reserved.
//

import Foundation

public enum Either<L, R> {
    case left(L)
    case right(R)
}

final public class Future<R> {

    private struct Join<L, R> {
        let left: L?
        let right: R?

        func with(left: L) -> Join<L, R> {
            return Join(left: left, right: self.right)
        }

        func with(right: R) -> Join<L, R> {
            return Join(left: self.left, right: right)
        }
    }

    private class Atomic<Value> {

        private let lock = DispatchSemaphore(value: 1)
        private var _value: Value

        init(value: Value) {
            _value = value
        }

        var value: Value {
            get { return _value }

            set (value) {
                lock.wait()
                defer { lock.signal() }
                _value = value
            }
        }
    }

    private class AtomicInteger {

        private let lock = DispatchSemaphore(value: 1)
        private var _value: Int

        init(value initialValue: Int = 0) {
            _value = initialValue
        }

        func decrementAndGet() -> Int {
            lock.wait()
            defer { lock.signal() }
            _value -= 1
            return _value
        }

        func incrementAndGet() -> Int {
            lock.wait()
            defer { lock.signal() }
            _value += 1
            return _value
        }
    }

    private class AtomicPromise<Value> {

        private let counter = AtomicInteger()
        private let result: Atomic<Value>
        private let maxConcurrent: Int
        private let complete: (Value) -> ()
        var value: Value { return self.result.value }

        init(value: Value, maxConcurrent: Int, complete: @escaping (Value) -> ()) {
            self.maxConcurrent = maxConcurrent
            self.complete = complete
            self.result = Atomic<Value>(value: value)
        }

        func push(value: Value) {
            self.result.value = value
            if (self.counter.incrementAndGet() == self.maxConcurrent) {
                self.complete(self.result.value)
            }
        }
    }

    public typealias Task = (@escaping (Try<R>) -> ()) -> ()

    public struct TimeoutError: Swift.Error {
        let timeout: DispatchTime
    }

    private(set) var value: Try<R>?
    private var queue: DispatchQueue
    private var callbacks: [(Try<R>) -> ()] = []

    public init(queue: DispatchQueue, complete: @escaping Task) {
        self.queue = queue
        queue.async { [weak self] in
            complete { value in
                self?.value = value
                self?.callbacks.forEach { $0(value) }
            }
        }
    }

    public convenience init(task: @escaping Task) {
        self.init(queue: DispatchQueue(label: "private future queue"), complete: task)
    }

    public convenience init(queue: DispatchQueue, value: Try<R>) {
        self.init(queue: queue) { $0(value) }
    }

    public convenience init(value: Try<R>) {
        self.init { $0(value) }
    }

    public static func failed(_ e: Swift.Error) -> Future<R> {
        return Future { $0(.failure(e)) }
    }

    public static func success(_ value: R) -> Future<R> {
        return Future { $0(.success(value)) }
    }
    
    @discardableResult
    public func respond(_ f: @escaping (Try<R>) -> ()) -> Future<R> {
        self.queue.async {
            switch self.value {
            case .some(let value): f(value)
            case .none: self.callbacks.append(f)
            }
        }
        return self
    }

    @discardableResult
    public func onSuccess(_ f: @escaping (R) -> ()) -> Future<R> {
        return self.respond { $0.onSuccess(f) }
    }

    @discardableResult
    public func onFailure(_ f: @escaping (Swift.Error) -> ()) -> Future<R> {
        return self.respond { $0.onFailure(f) }
    }

    public func foreach(_ f: @escaping (R) -> ()) -> Future<R> {
        return self.onSuccess(f)
    }

    public func map<R2>(_ f: @escaping (R) -> R2) -> Future<R2> {
        return self.transform { Future<R2>(queue: self.queue, value: $0.map(f)) }
    }

    public func flatMap<R2>(_ f: @escaping (R) -> Future<R2>) -> Future<R2> {
        return self.transform { result -> Future<R2> in
            switch result {
            case .success(let value): return f(value)
            case .failure(let error): return Future<R2>.failed(error)
            }
        }
    }

    public func transform<R2>(_ f: @escaping (Try<R>) -> Future<R2>) -> Future<R2> {
        return Future<R2>(queue: self.queue) { complete in
            self.respond { f($0).respond(complete)}
        }
    }

    public func filter(_ p: @escaping (R) -> Bool) -> Future<R> {
        return self.transform { Future<R>(queue: self.queue, value: $0.filter(p)) }
    }

    public func rescue(_ e: @escaping (Swift.Error) -> Future<R>) -> Future<R> {
        return self.transform { result -> Future<R> in
            switch result {
            case .success(let value): return Future<R>.success(value)
            case .failure(let error): return e(error)
            }
        }
    }

    public func or<R2>(_ other: Future<R2>) -> Future<Either<R, R2>> {
        return Future<Either<R, R2>> { complete in

            self.onSuccess { value in
                complete(.success(.left(value)))
            }.onFailure { error in
                complete(.failure(error))
            }

            other.onSuccess { value in
                complete(.success(.right(value)))
            }.onFailure { error in
                complete(.failure(error))
            }
        }
    }

    public func join<R2>(_ that: Future<R2>) -> Future<(R, R2)> {
        return Future<(R, R2)>(queue: self.queue) { complete in

            let promise = AtomicPromise<Join<R, R2>>(value:Join<R, R2>(left: nil, right: nil) , maxConcurrent: 2) { value in
                complete(.success((value.left!, value.right!)))
            }

            self.onSuccess { value in
                promise.push(value: promise.value.with(left: value))
            }.onFailure { error in
                complete(.failure(error))
            }

            that.onSuccess { value in
                promise.push(value: promise.value.with(right: value))
            }.onFailure { error in
                complete(.failure(error))
            }
        }
    }

    public func timeout(_ timeout: DispatchTimeInterval, forQueue: DispatchQueue) -> Future<R> {
        return Future<R>(queue: forQueue) { complete in

            let workItem = DispatchWorkItem {
                self.detach()
                complete(.failure(TimeoutError(timeout: .now())))
            }

            forQueue.asyncAfter(deadline: .now() + timeout, execute: workItem)

            self.respond { result in
                workItem.cancel()
                complete(result)
            }
        }
    }

    public func observe(queue: DispatchQueue) -> Future<R> {
        return Future<R>(queue: queue) { complete in
            self.respond { (result: Try<R>) in queue.async { complete(result) } }
        }
    }
}

