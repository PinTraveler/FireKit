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

enum PTObserverError: Error {
    case decodeError
}

public class FirestoreObjectObserver<T: Codable>: ObservableObject {
    @Published var data: T? = nil
    var listener: ListenerRegistration? = nil
    var ref: DocumentReference
    var onChange: ((Result<T, Error>) -> Void)? = nil
    
    init(ref: DocumentReference, onChangeHandler: @escaping ((Result<T, Error>) -> Void)) {
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
                self.onChange?(.failure(PTObserverError.decodeError))
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
