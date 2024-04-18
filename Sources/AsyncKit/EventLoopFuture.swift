//
//  File.swift
//  
//
//  Created by Jon Lund on 4/18/24.
//

//enum Result<T> {
//	case success(T)
//	case failure(Error)
//}
import UIKit

public typealias EventLoopFuture = Future
public typealias EventLoopPromise = Promise

public class Future<T> {
	private var result: Result<T, Error>?
	private var completionHandlers: [(Result<T, Error>) -> Void] = []
	private var successHandlers: [(T) -> Void] = []
	
	public init() {}
	
	public func complete(with result: Result<T,Error>) {
		guard self.result == nil else {
			assert(false,"Already have a result")
			return
		}
		self.result = result
		for handler in completionHandlers {
			handler(result)
		}
		if case .success(let value) = result {
			successHandlers.forEach { $0(value) }
		}
		completionHandlers = []
	}
	
	public func addCompletionHandler(handler: @escaping (Result<T, Error>) -> Void) {
		if let result = result {
			handler(result)
		} else {
			completionHandlers.append(handler)
		}
	}
	
	public func map<U>(transform: @escaping (T) -> U) -> Future<U> {
		let newFuture = Future<U>()
		addCompletionHandler { result in
			switch result {
			case .success(let value):
				let transformedValue = transform(value)
				newFuture.complete(with: .success(transformedValue))
			case .failure(let error):
				newFuture.complete(with: .failure(error))
			}
		}
		return newFuture
	}
	
	public func flatMap<U>(transform: @escaping (T) -> Future<U>) -> Future<U> {
		let newFuture = Future<U>()
		addCompletionHandler { result in
			switch result {
			case .success(let value):
				let futureU = transform(value)
				futureU.addCompletionHandler { resultU in
					switch resultU {
					case .success(let finalValue):
						newFuture.complete(with: .success(finalValue))
					case .failure(let error):
						newFuture.complete(with: .failure(error))
					}
				}
			case .failure(let error):
				newFuture.complete(with: .failure(error))
			}
		}
		return newFuture
	}

	public func flatMapMaybe() -> Future<T?> {
		let promise = Promise<Optional<T>>()
		addCompletionHandler { result in
			switch result {
			case .success(let value):
				promise.succeed(value)
			case .failure(let error):
				promise.succeed(nil)
			}
		}
		return promise.futureResult
	}

	public func whenCompleteBlocking(onto queue: DispatchQueue, _ callbackMayBlock: @escaping (Result<T, Error>) -> Void) {
		completionHandlers.append(callbackMayBlock)
	}
	
	public func whenSuccessBlocking(onto queue: DispatchQueue, _ callbackMayBlock: @escaping (T) -> Void) {
		successHandlers.append(callbackMayBlock)
	}
	
	public func transform<T>(to instance: @escaping @autoclosure () -> T) -> EventLoopFuture<T> {
		return self.map { _ in instance() }
	}
}


public class Promise<T> {
	let future: Future<T>
	
	public var futureResult: Future<T> { future }
	
	public init() {
		future = Future<T>()
	}
	
	public func succeed(_ value: T) {
		future.complete(with: .success(value))
	}
	
	public func completeWith(_ value: T) {
		future.complete(with: .success(value))
	}
	
	@available(*, deprecated, message: "Not built yet")
	public func completeWith(_ future: Future<T>) {
		assert(false,"Not built")
	}
	
	func reject(with error: Error) {
		future.complete(with: .failure(error))
	}
	
	public func fail(_ error: Error) {
		future.complete(with: .failure(error))
	}
}


extension Array {
	public func flatten<T>(on: EventLoop) -> Future<[T]> where Element == Future<T> {
		let promise = Promise<[T]>()
		var results = [Any?](repeating: nil, count: self.count)
		var completedCount = 0
		var hasFailed = false
		
		for (index, future) in self.enumerated() {
			future.addCompletionHandler { result in
				switch result {
				case .success(let value):
					if !hasFailed {
						results[index] = value
						completedCount += 1
						if completedCount == self.count {
							promise.succeed( results.compactMap { $0 as! T })
						}
					}
				case .failure(let error):
					if !hasFailed {
						hasFailed = true
						promise.reject(with: error)
					}
				}
			}
		}
		
		return promise.future
	}
}

public struct EventLoop {
	@inlinable
	public func makePromise<T>(of type: T.Type = T.self) -> Promise<T> {
		return Promise<T>()
	}
	
	@inlinable
	public func makeSucceededFuture<Success>(_ value: Success) -> Future<Success> {
		let f = Future<Success>()
		DispatchQueue.main.async {
			f.complete(with: .success(value))
		}
		return f
	}
	
	@available(*, deprecated, message: "Not built yet")
	public func completeWith<T>(_ future: Future<T>) {
		assert(false,"Not built")
	}
	
	public func flatten<T>(_ futures: [Future<T>]) -> Future<[T]> {
		return futures.flatten(on: self)
	}
}

public struct MultiThreadedEventLoopGroup {
	let loops: [EventLoop]
	
	public init(numberOfThreads: Int) {
		loops = [EventLoop()]
	}
	
	public func next() -> EventLoop {
		return loops.first!
	}
	
	public func future<T>(_ val: T) -> Future<T> {
		fatalError()
	}
}
