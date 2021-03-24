//
//  File.swift
//  
//
//  Created by can ersoz on 23.03.2021.
//

import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift


public class FireCollectionManager<T>: ObservableObject where T: Codable, T: Comparable, T: FireIdentifiable {
    @Published var data: [T] = []
    var listener: ListenerRegistration? = nil
    var ref: CollectionReference?
    var query: Query?
    var onEvent: ((_ event: DocumentChangeType, _ elem: T?) -> Void)? = nil
    
    public init(ref: CollectionReference? = nil, query: Query? = nil, onEvent: ((_ event: DocumentChangeType, _ elem: T?) -> Void)? = nil) {
        self.ref = ref
        self.query = query
        self.onEvent = onEvent
    }
    
    public func setRef(ref: CollectionReference, query: Query?, onEvent: ((_ event: DocumentChangeType, _ elem: T?) -> Void)?) {
        self.stopListener()
        self.ref = ref
        self.query = query != nil ? query : ref
        
        self.onEvent = onEvent
    }
    
    public func insertionIndexOf(_ elem: T) -> Int {
        let i = self.data.firstIndex(where: { $0 <= elem })
        guard let index = i else { return self.data.count }
        return index
    }
    
    open func onInternalAdd(_ elem: T) {
        self.data.insert(elem, at: insertionIndexOf(elem))
        onEvent?(.added, elem)
    }
    
    open func onInternalChange(_ elem: T) {
        guard let i = self.data.firstIndex(of: elem) else { return }
        self.data[i] = elem
        onEvent?(.modified, elem)
    }
    
    open func onInternalRemove(_ elem: T) {
        guard let i = self.data.firstIndex(of: elem) else { return }
        self.data.remove(at: i)
        onEvent?(.removed, elem)
    }
    
    open func onBatchChanges(changes: [T]) { }
    
    open func startListener() {
        guard let query = query else {
            print("FireCollectionManager: Error Starting Listener. No Query Object Provided. Please call setRef before startListener!")
            return
        }
        listener = query.addSnapshotListener { snapshot, error in
            if let error = error {
                print("FireCollectionManager: Error listening for changes ", error)
                return
            }
            
            guard let snapshot = snapshot else {
                print("FireCollectionManager: Returned nil snapshot")
                return
            }
            
            var changes: [T] = []
            
            snapshot.documentChanges.forEach{ change in
                guard let elem = try? change.document.data(as: T.self) else { return }
                changes.append(elem)
                switch(change.type) {
                case .added:
                    if self.data.contains(elem){ self.onInternalChange(elem) }
                    else { self.onInternalAdd(elem) }
                case .modified:
                    if self.data.contains(elem){ self.onInternalChange(elem) }
                    else { self.onInternalAdd(elem) }
                case .removed:
                    if self.data.contains(elem) { self.onInternalRemove(elem) }
                }
            }
            self.onBatchChanges(changes: changes)
        }
    }
    
    open func stopListener() {
        listener?.remove()
        listener = nil
        data = []
    }
    
    // Commits all elements in the data array regardless of whether they have been changed
    open func commitAll(completion: (()-> Void)? = nil){}
    
    // Commits the element at the given index (data[i])
    open func commit(at index: Int, completion: (()-> Void)? = nil){}
    
    // Commits the given element regardless of whether it is in data. This is equivalent to insert if the element does not exist
    open func commit(_ elem: T, completion: (()-> Void)? = nil){}
    
    // Removes the document with the given id if one exists
    open func remove(by id: String, completion: ((Result<Void, Error>)-> Void)? = nil){
        guard let ref = ref else { completion?(.failure(FireError.nilReferenceError)); return }
        ref.document(id).delete(){ error in
            if let error = error { completion?(.failure(error)) }
            else { completion?(.success(())) }
        }
    }
    
    open func remove(at index: Int, completion: ((Result<Void, Error>)-> Void)? = nil){
        if index < 0 || index >= self.data.count {
            completion?(.failure(FireError.indexOutOfBoundsError))
            return
        }
        guard let id = self.data[index].id else {
            completion?(.failure(FireError.nilIDError))
            return
        }
        remove(by: id, completion: completion)
    }
    
    open func remove(at indices: [Int], completion: ((Result<Void, Error>)-> Void)? = nil){
        let group = DispatchGroup()
        indices.forEach{ i in
            group.enter()
            remove(at: i){ _ in group.leave() }
        }
        group.notify(queue: .main) {
            completion?(.success(())) //TODO: This hides internal errors.
        }
    }
    
    open func insert(_ elem: T, completion: ((Result<Void, Error>)-> Void)? = nil) {
        print("FirestoreCollectionManager: Commiting Data ", data)
        guard let id = elem.id else {
            completion?(.failure(FireError.nilIDError))
            return
        }
        guard let ref = ref else { completion?(.failure(FireError.nilReferenceError)); return }
        do {
            // try burda error throw ettiren olay galiba?
            try ref.document(id).setData(from: elem, merge: true) { error in
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
