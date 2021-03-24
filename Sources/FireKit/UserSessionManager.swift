//
//  PTUserSessionManager.swift
//  Goals
//
//  Created by cem ersoz on 23.01.2021.
//

import Foundation
import FirebaseAuth

enum PTUserSessionError: Error {
    case unknownAuthError
    case missingUser
}

public enum PTAuthenticationState {
    case initializing
    case authenticated
    case unauthenticated
}

open class UserSessionManager: ObservableObject {
    
    @Published public var userReady: Bool = false
    @Published public var isNew = false
    @Published public var state: PTAuthenticationState = .initializing
    
    @Published public var userID: String? {
        didSet { userReady = getUserReady() }
    }
    
    let defaultToAnonymousUser: Bool
    let onAuth: (() -> Void)?
    
    public init(defaultToAnonymousUser: Bool = false, onAuth: (() -> Void)? = nil ){
        self.defaultToAnonymousUser = defaultToAnonymousUser
        self.onAuth = onAuth
    }
    
    
    public var initialized: Bool {
        state != .initializing
    }
    
    public var isAnonymous: Bool {
        Auth.auth().currentUser?.isAnonymous ?? false
    }
    
    public var email: String {
        Auth.auth().currentUser?.email ?? ""
    }
    
    
    // MARK: - Exposed Callbacks
    
    open func onAnonymousSessionStart() { }
    open func getUserReady() -> Bool {
        userID != nil
    }
    
    // Called on new FirebaseAuth sessions, triggered by Auth.stateChangedListener started in startAuthListener
    open func onAuthSessionStart(user: FirebaseAuth.User?, error: Error?) {
        print("PTUserSessionManager: Auth Session Started")
        guard let user = user else {
            print("PTUserSessionManager: Auth Session Started (No User)")
            state = .unauthenticated
            userID = nil
            return
        }
        
        userID = user.uid
        state = .authenticated
        onAuth?()
    }
    
    open func onAuthSessionEnd() {
        print("PTUserSessionManager: Auth Session Ended")
    }
    
    // MARK: - Auth Session Lifecycle
    
    open func startAnonymousSession() {
        print("PTUserSessionManager: Starting Anonymous Session")
        Auth.auth().signInAnonymously() { (authResult, error) in
            if let error = error {
                print("PTUserSessionManager: Starting Anonymous Session (ERROR)")
                print("PTUserSessionManager: ", error)
                self.state = .unauthenticated
                return
            }
            print("PTUserSessionManager: Starting Anonymous Session (STARTED)")
            self.state = .authenticated
            self.isNew = true
        }
    }
    
    open func onAuthStateChanged(auth: Auth, user: FirebaseAuth.User?) {
        print("PTUserSessionManager: Auth State Changed")
        if let user = user {
            print("PTUserSessionManager: Auth State Changed -- User")
            // User found -- call completion to handle any post-reauth workflow
            onAuthSessionStart(user: user, error: nil)
        } else if defaultToAnonymousUser {
            print("PTUserSessionManager: Auth State Changed -- No User (Anon)")
            // No user logged in and we want to default to anonymous user. Start an Anonymous User Session
            startAnonymousSession()
        } else if state == .authenticated {
            print("PTUserSessionManager: Auth State Changed -- No User (Signout)")
            // A user just signed out (i.e. we've gone from user to no user)
            state = .unauthenticated
            userID = nil
            onAuthSessionEnd()
        } else {
            print("PTUserSessionManager: Auth State Changed -- No User")
            state = .unauthenticated
            userID = nil
        }
    }
    
    open func startAuthListener() {
        print("PTUserSessionManager: Auth Listener Started")
        Auth.auth().addStateDidChangeListener(onAuthStateChanged)
    }
    
    // MARK: - Password Changes
    
    open func changePasswordRequest(replace oldPassword: String, with newPassword: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        let user = Auth.auth().currentUser
        let credentials = EmailAuthProvider.credential(withEmail: email, password: oldPassword)
        user?.reauthenticate(with: credentials, completion: { (result, error) in
            if let error = error {
                completion?(.failure(error))
            } else {
                // User re-authenticated.
                user?.updatePassword(to: newPassword){ error in
                    if let error = error { completion?(.failure(error)) }
                    else { completion?(.success(())) }
                }
            }
        })
    }
    
    open func forgetPassword(email: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        Auth.auth().sendPasswordReset(withEmail: email) { error in
            if let error = error {
                print(#fileID, #line, #function, error)
                completion?(.failure(error))
            }
            else {
                completion?(.success(()))
            }
        }
    }
    
    
    // MARK: - Link Credentials
    open func linkAuth(with email: String, password: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        print("PTUserSessionManager: Linking User with Email Auth")
        let credentials = EmailAuthProvider.credential(withEmail: email, password: password)
        Auth.auth().currentUser?.link(with: credentials) { result, error in
            if let error = error {
                print("PTUserSessionManager: Error Linking")
                print(#fileID, #line, #function, error)
                completion?(.failure(error))
                return
            }
            
            self.isNew = false
            completion?(.success(()))
        }
    }
    
    
    // MARK: - Login & Signup
    
    open func signup(email: String, password: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        print("PTUserSessionManager: Signing Up")
        if defaultToAnonymousUser {
            print("PTUserSessionManager: Signing Up (Link Anon)")
            linkAuth(with: email, password: password, completion: completion)
        } else {
            print("PTUserSessionManager: Signing Up (New User)")
            self.isNew = true
            Auth.auth().createUser(withEmail: email, password: password) { authResult, error in
                //TODO: Not Tested, blatantly plagiarised from @canersoz02
                if let error = error {
                    print("PTUserSessionManager: Signing Up (Error)")
                    print("PTUserSessionManager: ", error)
                    self.isNew = false
                    completion?(.failure(error))
                } else if authResult != nil {
                    print("PTUserSessionManager: Signing Up (Success)")
                    completion?(.success(()))
                } else {
                    self.isNew = false
                    completion?(.failure(PTUserSessionError.unknownAuthError))
                }
            }
        }
    }
    
    open func login(email: String, password: String, completion: ((Result<FirebaseAuth.User, Error>) -> Void)? = nil) {
        print("PTUserSessionManager: Logging In")
        let oldSession = Auth.auth().currentUser
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            if let error = error {
                print("PTUserSessionManager: Logging In (Error)")
                print(#fileID, #line, #function, error)
                completion?(.failure(error))
            }
            else if let user = result?.user {
                self.userID = user.uid
                print("PTUserSessionManager: Logging In (Success)")
                
                // Delete old anon session if we login with an existing non-anon session
                if oldSession?.isAnonymous == true {
                    oldSession?.delete { error in
                        print("PTUserSessionManager: Logging In (Deleted Anon)")
                        if let error = error {
                            print("PTUserSessionManager: Logging In (Error Deleting Anon)")
                            print(#fileID, #line, #function, error) }
                    }
                }
                self.isNew = false
                completion?(.success(user))
            }
            else {
                completion?(.failure(PTUserSessionError.unknownAuthError))
            }
        }
    }
    
    open func signout() {
        print("PTUserSessionManager: Signing out")
        do {
            try Auth.auth().signOut()
        } catch {
            print(#fileID, #line, #function, error)
        }
    }
}
