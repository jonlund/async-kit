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

#if DEBUG
//internal var futureCount: Int = 0
internal var futures: [String:Int] = [:]
#endif

public class Future<T> {
	typealias Element = T
	
	private var result: Result<T, Error>?
	private var completionHandlers: [(Result<T, Error>) -> Void] = []
	private var successHandlers: [(T) -> Void] = []
	private var errorHandlers: [(Error) -> Void] = []
	
	#if DEBUG
	private var didComplete: Bool = false
	private let key: String
	#endif
	
#if DEBUG
	var futureCount: Int { futures.map({$0.value}).reduce(0) { $0 + $1 } }
	
	public init(file: String = #file, function: String = #function, line: Int = #line) {
		//futureCount += 1
		key = "\(file) \(function) [Line \(line)]"
		futures[key] = (futures[key] ?? 0) + 1
		DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(15)) {
			if self.didComplete == false {
				print("\(self.key): future DID NOT complete!")
				assert(false,"This didn't complete!")
			}
			else {
				print("\(self.key): complete")
			}
			print("***** \(self.futureCount)\tOutstanding Futures")
		}
	}
	#else
	public init() {}
#endif
	
	deinit {
		#if DEBUG
		assert(result != nil, "Result must be something non-nil, or it means the promise went out of scope before completion")
		#endif
	}
	
	
	// MARK: - Completions

	public func complete(with result: Result<T,Error>) {
		guard self.result == nil else {
			assert(false,"Already have a result")
			return
		}
		
		#if DEBUG
		//futureCount += 1
		futures[key] = futures[key]! - 1
		#endif
		
		self.result = result
		for handler in completionHandlers {
			handler(result)
		}
		
		switch result {
		case .success(let value): successHandlers.forEach { $0(value) }
		case .failure(let error): errorHandlers.forEach { $0(error) }
		}
		completionHandlers = []
		
		#if DEBUG
		self.didComplete = true
		#endif
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
	
//	@available(*, deprecated, message: "NOT BUILT YET")
//	@inlinable
//	public func flatMapBlocking<NewValue>(onto queue: DispatchQueue, _ callbackMayBlock: @escaping (T) throws -> NewValue) -> Future<NewValue> {
//		//self._flatMapBlocking(onto: queue, callbackMayBlock)
//		return self.flatMap { result in
//			switch result {
//			case .success(let value): ()
//			case .failure(_): ()
//			}
//			fatalError()
//		}
//		//fatalError("Not built yet")
//	}

	public func flatMapBlocking<U>(onto queue: DispatchQueue, transform: @escaping (T) -> Future<U>) -> Future<U> {
		return self.flatMap(transform: transform)
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
		
	public func whenComplete(_ callbackMayBlock: @escaping (Result<T, Error>) -> Void) {
		self.addCompletionHandler(handler: callbackMayBlock)
	}
	
	public func whenCompleteBlocking(onto queue: DispatchQueue, _ callbackMayBlock: @escaping (Result<T, Error>) -> Void) {
		self.addCompletionHandler(handler: callbackMayBlock)
	}
	
	
	// MARK: - Successes

	private func _addSuccessHandler(handler: @escaping (T) -> Void) {
		if let result = result {
			if case .success(let x) = result {
				handler(x)
				return
			}
		} else {
			successHandlers.append(handler)
		}
	}
	
	public func whenSuccess(_ callbackMayBlock: @escaping (T) -> Void) {
		_addSuccessHandler(handler: callbackMayBlock)
	}
	
	public func whenSuccessBlocking(onto queue: DispatchQueue, _ callbackMayBlock: @escaping (T) -> Void) {
		_addSuccessHandler(handler: callbackMayBlock)
	}
	
	
	// MARK: - Failures
	
	private func _addFailureHandler(handler: @escaping (Error) -> Void) {
		if let result = result {
			if case .failure(let x) = result {
				handler(x)
				return
			}
		} else {
			errorHandlers.append(handler)
		}
	}
	
	public func whenFailure(_ callbackMayBlock: @escaping (Error) -> Void) {
		_addFailureHandler(handler: callbackMayBlock)
	}

	public func whenFailureBlocking(onto queue: DispatchQueue, _ callbackMayBlock: @escaping (Error) -> Void) {
		_addFailureHandler(handler: callbackMayBlock)
	}
	
	public func transform<T>(to instance: @escaping @autoclosure () -> T) -> Future<T> {
		return self.map { _ in instance() }
	}
	
	public func flatMapThrowing<U>(_ callback: @escaping (T) throws -> U) -> Future<U> {
		let promise = Promise<U>()
		self.addCompletionHandler { result in
			switch result {
			case .success(let value):
				do {
					let mapped: U = try callback(value)
					promise.succeed(mapped)
				}
				catch {
					promise.fail(error)
				}
			case .failure(let error):
				promise.fail(error)
			}
		}
		return promise.futureResult
	}
	
	public func wait() throws -> T {
		if let result = result {
			switch result {
			case .success(let value):	return value
			case .failure(let error):	throw error
			}
		}

		var awaitedValue: Result<T, Error>? = nil
		let group = DispatchGroup()
		group.enter()
		self.addCompletionHandler { result in
			awaitedValue = result
			group.leave()
		}
		
		group.wait()

		guard let result = awaitedValue else {
			throw AsyncError.systemError
		}
		switch result {
		case .success(let value):	return value
		case .failure(let error):	throw error
		}
	}
	
	@inlinable
	public func unwrap<NewValue>(orError error: Error) -> EventLoopFuture<NewValue> where T == Optional<NewValue> {
		return self.flatMapThrowing { (value) throws -> NewValue in
			guard let value = value else {
				throw error
			}
			return value
		}
	}

}


public class Promise<T> {
	let future: Future<T>
	
	public var futureResult: Future<T> { future }
	
	#if DEBUG
	public init(file: String = #file, function: String = #function, line: Int = #line) {
		future = Future<T>(file: file, function: function, line: line)
	}
	#else
	public init() {
		future = Future<T>()
	}
	#endif
		
	
	public func succeed(_ value: T) {
		future.complete(with: .success(value))
	}
	
	public func completeWith(_ value: T) {
		future.complete(with: .success(value))
	}
	
	//@available(*, deprecated, message: "Not built yet")
	public func completeWith(_ future: Future<T>) {
		future.whenComplete { result in
			self.future.complete(with: result)
		}
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
		
		if self.count < 1 {
			DispatchQueue.main.asyncAfter(deadline: .now()) {
				promise.succeed([])
			}
			return promise.future
		}
		
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
	#if DEBUG
	@inlinable
	public func makePromise<T>(of type: T.Type = T.self, file: String = #file, function: String = #function, line: Int = #line) -> Promise<T> {
		return Promise<T>(file: file, function: function, line: line)
	}
	#else
	@inlinable
	public func makePromise<T>(of type: T.Type = T.self) -> Promise<T> {
		return Promise<T>()
	}
	#endif
	
	public func future<T>(_ value: T) -> Future<T> {
		return makeSucceededFuture(value)
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
	
	@inlinable
	public func makeFailedFuture<T>(_ error: Error) -> Future<T> {
		let f = Future<T>()
		f.complete(with: .failure(error))
		return f
	}
	
	@discardableResult
	//@preconcurrency
	public func scheduleTask<T>(in amt: TimeAmount, _ task: @escaping () -> T) -> Scheduled<T> {
//		let promise: Promise<T> = .init()
//		promise.future.addCompletionHandler { result in
//			switch result {
//			case .success(let value): try? task()
//			case .failure(let error): ()
//			}
//		}
//		DispatchQueue.main.asyncAfter(deadline: amt.dispatchTime) {
//			promise.s
//		}
//
//		return Scheduled(promise: promise) {
//			promise.fail(AsyncError.canceled)
//		}
		let scheduled = Scheduled(task: task)
		scheduled.scheduleFor(amt: amt)
		return scheduled
	}

}

public enum AsyncError: Error {
	case canceled
	case systemError
	case teapot
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


public enum TimeAmount {
	case seconds(Int)
	
	var dispatchTime: DispatchTime {
		switch self {
		case .seconds(let s):	return DispatchTime.now() + .seconds(s)
		}
	}
}


public class Scheduled<T> {
//	private let _promise: Promise<T>
	private var _task: (() -> T)?	// will make nil if cancelled
//	private let _cancellationTask: () -> Void
	
//	public init(promise: Promise<T>, cancellationTask: @escaping () -> Void) {
//		_promise = promise
//		_cancellationTask = cancellationTask
//	}

	public init(task: @escaping () -> T) {
		_task = task
		//_cancellationTask = cancellationTask
	}
	
	public func scheduleFor(amt: TimeAmount) {
		DispatchQueue.main.asyncAfter(deadline: amt.dispatchTime) {
			self.run()
		}
	}
	
	internal func run() {
		self._task?()
	}
	
	public func cancel() {
		self._task = nil
		//self._cancellationTask()
	}
}
