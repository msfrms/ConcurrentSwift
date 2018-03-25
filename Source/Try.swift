//
// Created by Radaev Mikhail on 22.01.2018.
// Copyright (c) 2018 Radaev Mikhail. All rights reserved.
//

import Foundation

public enum Try<R> {

    public struct NoSuchElementError: Swift.Error {
        let message: String
    }

    case success(R)
    case failure(Swift.Error)

    public init(value: R) {
        self = .success(value)
    }

    public init(error: Swift.Error) {
        self = .failure(error)
    }

    @discardableResult
    public func onSuccess(_ f: (R) -> ()) -> Try<R> {
        switch self {
        case .success(let result): f(result)
        default: ()
        }
        return self
    }

    @discardableResult
    public func onFailure(_ f: (Swift.Error) -> ()) -> Try<R> {
        switch self {
        case .failure(let error): f(error)
        default: ()
        }
        return self
    }

    public func getOrElse(_ defaultValue: R) -> R {
        switch self {
        case .success(let result): return result
        case .failure: return defaultValue
        }
    }

    public func get() throws -> R {
        switch self {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    public func foreach(_ f: (R) -> ()) {
        self.onSuccess(f)
    }

    public func transform<R2>(_ f: (R) -> (Try<R2>)) -> Try<R2> {
        switch self {
        case .success(let result): return f(result)
        case .failure(let error): return .failure(error)
        }
    }

    public func flatMap<R2>(_ f: (R) -> Try<R2>) -> Try<R2> {
        return self.transform(f)
    }

    public func map<R2>(_ f: (R) -> R2) -> Try<R2> {
        return self.transform { Try<R2>(value: f($0)) }
    }

    public func handle(_ e: (Swift.Error) -> R) -> Try<R> {
        return self.rescue { error -> Try<R> in .success(e(error)) }
    }

    public func rescue(_ e: (Swift.Error) -> Try<R>) -> Try<R> {
        switch self {
        case .failure(let error): return e(error)
        case .success: return self
        }
    }

    public func filter(_ p: (R) -> Bool) -> Try<R> {
        return self.transform { value -> (Try<R>) in
            if p(value) {
                return self
            } else {
                return .failure(NoSuchElementError(message: "Predicate does not hold for \(value)"))
            }
        }
    }
}


