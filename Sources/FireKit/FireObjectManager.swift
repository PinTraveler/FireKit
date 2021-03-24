//
//  PTFirestoreObservableObject.swift
//  Goals
//
//  Created by elif ersoz on 31.01.2021.
//

import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift
import SwiftUI

enum FireError: Error {
    case decodeError
    case indexOutOfBoundsError
    case nilIDError
    case nilReferenceError
    case nilQueryError
}

public protocol FireIdentifiable {
    var id: String? { get }
}

public class FireObjectManager<T>: ObservableObject where T: Codable, T: FireIdentifiable {
    @Published var data: T? = nil
    var listener: ListenerRegistration? = nil
    var ref: DocumentReference
    var onChange: ((Result<T, Error>) -> Void)? = nil
    
    init(ref: DocumentReference, onChangeHandler: ((Result<T, Error>) -> Void)? = nil) {
        self.ref = ref
        self.onChange = onChangeHandler
    }
    
    open func startListener() {
        listener = ref.addSnapshotListener { snapshot, error in
            if let error = error {
                self.onChange?(.failure(error))
                return
            }
            
            guard let data = try? snapshot?.data(as: T.self) else {
                self.onChange?(.failure(FireError.decodeError))
                return
            }
            
            self.data = data
            self.onChange?(.success(data))
        }
    }
    
    open func stopListener(){
        listener?.remove()
        listener = nil
    }
    
    open func commit(completion: ((Result<Void, Error>) -> Void)?) {
        print("FirestoreObjectObserver: Commiting Data ", data)
        do {
            // try burda error throw ettiren olay galiba?
            try ref.setData(from: data, merge: true) { error in
                if let error = error {
                    completion?(.failure(error))
                } else {
                    completion?(.success(()))
                }
            }
        } catch {
            completion?(.failure(error))
        }
    }
}
