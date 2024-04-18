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

public typealias EventLoopFuture = Future
public typealias EventLoopPromise = Promise

public class Future<T> {
	private var result: Result<T, Error>?
	private var completionHandlers: [(Result<T, Error>) -> Void] = []
	
	func complete(with result: Result<T,Error>) {
		guard self.result == nil else {
			assert(false,"Already have a result")
			return
		}
		self.result = result
		for handler in completionHandlers {
			handler(result)
		}
		completionHandlers = []
	}
	
	func addCompletionHandler(handler: @escaping (Result<T, Error>) -> Void) {
		if let result = result {
			handler(result)
		} else {
			completionHandlers.append(handler)
		}
	}
}


public class Promise<T> {
	let future: Future<T>
	
	init() {
		future = Future<T>()
	}
	
	func fulfill(with value: T) {
		future.complete(with: .success(value))
	}
	
	func reject(with error: Error) {
		future.complete(with: .failure(error))
	}
}


