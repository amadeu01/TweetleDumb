//
//  AuthenticationController.swift
//  TweetleDumb
//
//  Created by Ian Keen on 2017-06-13.
//  Copyright © 2017 Mustard. All rights reserved.
//

import Foundation

protocol AuthenticationControllerDelegate {
    func authenticationError(controller: AuthenticationController, error: Swift.Error)
    func authenticationLogin(controller: AuthenticationController, authentication: Authentication)
    func authenticationLogout(controller: AuthenticationController)
}

extension AuthenticationController {
    enum StorageKey {
        static let authentication = "authentication"
    }
}

/// AuthenticationController is responsible for pairing an external auth with the
/// apps backend and keeping track of the authentication state for this session
final class AuthenticationController {
    // MARK: - Private Properties
    private let api: API
    private let storage: KeyValueStore
    private let authenticators: [Authenticator]

    // MARK: - Public Properties
    let delegates = MulticastDelegate<AuthenticationControllerDelegate>()
    private(set) var authentication: Authentication? {
        didSet {
            switch (oldValue, authentication) {
            case (.some, .none): // logged in > logout
                authenticators.forEach { $0.logout() }
                delegates.notify { $0.authenticationLogout(controller: self) }

            case (.none, .some(let auth)): // logged out > login
                store(authentication: auth)
                delegates.notify { $0.authenticationLogin(controller: self, authentication: auth) }

            default:
                // invalid transition's are:
                // - logged in > login
                // - logged out > logout
                print("This transition shouldn't happen")
            }
        }
    }

    // MARK: - Lifecycle
    init(api: API, storage: KeyValueStore, authenticators: [Authenticator]) {
        self.api = api
        self.storage = storage
        self.authenticators = authenticators

        // we assign a value here so we don't trigger the property observer
        authentication = storedAuthentication()
    }

    // MARK: - Public Functions
    func notifyDelegate() {
        switch authentication {
        case .none:
            delegates.notify { $0.authenticationLogout(controller: self) }

        case .some(let auth):
            delegates.notify { $0.authenticationLogin(controller: self, authentication: auth) }
        }
    }
    func login<T: Authenticator>(using authenticator: T.Type) {
        guard authentication == nil
            else { return send(error: Error.alreadyLoggedIn) }

        guard let authenticator = authenticators.first(where: { $0 is T })
            else { return send(error: Error.unsupportedAuthenticator) }

        authenticator.login { [weak self] result in
            guard let this = self else { return }

            switch result {
            case .failure(let error):
                this.send(error: error)

            case .success(let token):
                let request = AuthenticationRequest(
                    authenticator: authenticator.name,
                    token: token
                )

                this.api.execute(
                    request: request,
                    complete: { response in
                        switch response {
                        case .failure(let error):
                            this.send(error: error)

                        case .success(let auth):
                            this.authentication = auth
                        }
                    }
                )

            }
        }
    }
    func logout() {
        guard authentication != nil
            else { return send(error: Error.alreadyLoggedOut) }

        authentication = nil
    }

    // MARK: - Private Functions
    private func storedAuthentication() -> Authentication? {
        guard let json: [String: Any] = storage.get(key: StorageKey.authentication)
            else { return nil }

        return try? Authentication(json: json)
    }
    private func store(authentication: Authentication) {
        storage.set(
            value: authentication.makeDictionary(),
            forKey: StorageKey.authentication
        )
    }
    private func clearAuthentication() {
        storage.remove(key: StorageKey.authentication)
    }
    private func send(error: Swift.Error) {
        delegates.notify { $0.authenticationError(controller: self, error: error) }
    }
}
