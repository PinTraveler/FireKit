//
//  PTUserSessionProfileManager.swift
//  Goals
//
//  Created by cem ersoz on 23.01.2021.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

open class UserSessionProfileManager<T: Codable>: UserSessionManager {
    
    // Note: Replicated here for State Update Propagation
    // Need to find a better way
    @Published public var profile: T? = nil
    
    var profileObserver: FirestoreObjectObserver<T>? = nil
    
    public let profileCollection: CollectionReference = Firestore.firestore().collection("profile")
    
    override open func getUserReady() -> Bool {
        super.getUserReady() && profile != nil
    }
    
  
    // MARK: - Abstract Functions
    
    open func getDefaultProfile(user: FirebaseAuth.User) -> T {
        preconditionFailure("This method must be overridden")
    }
    
    open func getProfileForUser(user: FirebaseAuth.User) -> T {
        preconditionFailure("This method must be overriden")
    }
    
    // MARK: - Exposed Callbacks
    
    open func updateProfile(user: FirebaseAuth.User) { }
    open func onProfileChange() { }
    
    
    // MARK: - Profile Update
    
    open func commitProfile(completion: ((Result<Void, Error>) -> Void)? = nil) {
        print("PTUserSessionProfileManager: Updating Profile Object")
        profileObserver?.commit(completion: completion)
    }
    
    
    // MARK: - Profile Lifecycle Methods
    
    open func startSession() {
        print("PTUserSessionProfileManager: Starting Session")
        guard let userID = userID, profileObserver == nil else {
            print("PTUserSessionProfileManager: Starting Session (Already Started)")
            return
        }
        
        profileObserver = FirestoreObjectObserver(ref: profileCollection.document(userID)) { result in
            print("PTUserSessionProfileManager: Profile Changed")
            switch(result){
            case .success(let data):
                self.profile = data
                self.onProfileChange()
            case .failure(let error):
                print("PTUserSessionProfileManager: Profile Changed (Error)")
                print(#fileID, #line, #function, "No document", error)
                self.signout()
                return
            }
        }
        profileObserver?.startListener()
    }
    
    open func endSession() {
        print("PTUserSessionProfileManager: Ending Session")
        profile = nil
        profileObserver?.stopListener()
        profileObserver = nil
    }
    
    
    // MARK: - Override Auth Events
    
    override open func onAuthSessionStart(user: FirebaseAuth.User?, error: Error?) {
        super.onAuthSessionStart(user: user, error: error)
        guard let user = user else { return } //TODO: Maybe trigger end session, etc
        self.endSession()
        if user.isAnonymous && isNew {
            //TODO: commitProfile should just be self.profile.commit
            self.profileObserver?.data = self.getDefaultProfile(user: user)
            self.commitProfile(){ _ in self.startSession() }
        }
        else if isNew {
            self.profileObserver?.data = self.getProfileForUser(user: user)
            self.commitProfile(){ _ in self.startSession() }
        }
        else{
            self.startSession()
        }
    }
    
    override open func signup(email: String, password: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        super.signup(email: email, password: password) { result in
          switch result{
          case .success:
            if let user = Auth.auth().currentUser {
              self.updateProfile(user: user)
              self.commitProfile(completion: completion)
            }
            else {
              completion?(.failure(PTUserSessionError.unknownAuthError))
            }
          case .failure:
            completion?(result)
          }
        }
    }
    
  override open func login(email: String, password: String, completion: ((Result<FirebaseAuth.User, Error>) -> Void)? = nil) {
        super.login(email: email, password: password) { result in
          switch result {
          case .failure(let error):
            completion?(.failure(error))
          case .success(let user):
            self.updateProfile(user: user)
            self.commitProfile{ result in
              switch result {
              case .success:
                completion?(.success(user))
              case .failure(let error):
                completion?(.failure(error))
              }
            }
          }
        }
    }
    
    override open func signout() {
        super.signout()
        endSession()
    }
}
