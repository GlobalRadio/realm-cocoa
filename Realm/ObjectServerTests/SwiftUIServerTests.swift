////////////////////////////////////////////////////////////////////////////
//
// Copyright 2021 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

import RealmSwift
import XCTest
import SwiftUI
import Combine

#if canImport(RealmTestSupport)
import RealmSwiftSyncTestSupport
import RealmSyncTestSupport
#endif

@available(OSX 11, *)
class SwiftUIServerTests: SwiftSyncTestCase {
    override func setUp() {
        super.setUp()
        let config = Realm.Configuration(objectTypes: [SwiftHugeSyncObject.self])
        Realm.Configuration.defaultConfiguration = config
    }

    override func tearDown() {
        cancellables.forEach { $0.cancel() }
        cancellables = []
        super.tearDown()
    }

    var cancellables: Set<AnyCancellable> = []

    // MARK: - AsyncOpen
    func asyncOpen<T: BSON>(appId: String? = nil, partitionValue: T, timeout: UInt? = nil, handler: @escaping (AsyncOpenState) -> Void) {
        let asyncOpen = AsyncOpen(appId: appId, partitionValue: partitionValue, timeout: timeout)
        asyncOpen.projectedValue
            .sink { asyncOpenState in
                handler(asyncOpenState)
            }
            .store(in: &cancellables)
        waitForExpectations(timeout: 10.0)
        asyncOpen.cancel()
    }

    func testAsyncOpenOpenRealm() throws {
        _ = try logInUser(for: basicCredentials())

        let ex = expectation(description: "download-realm-async-open")
        asyncOpen(appId: appId, partitionValue: #function) { asyncOpenState in
            if case let .open(realm) = asyncOpenState {
                XCTAssertNotNil(realm)
                ex.fulfill()
            }
        }
    }

    func testAsyncOpenDownloadRealm() throws {
        let user = try logInUser(for: basicCredentials())
        if !isParent {
            populateRealm(user: user, partitionValue: #function)
            return
        }
        executeChild()

        let ex = expectation(description: "download-populated-realm-async-open")
        asyncOpen(appId: appId, partitionValue: #function) { asyncOpenState in
            if case let .open(realm) = asyncOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: SwiftSyncTestCase.bigObjectCount, realm, SwiftHugeSyncObject.self)
                ex.fulfill()
            }
        }
    }

    func testAsyncOpenWaitingForUserWithoutUserLoggedIn() throws {
        let user = try logInUser(for: basicCredentials())
        user.logOut { _ in } //Logout current user

        let ex = expectation(description: "download-realm-async-open-not-logged")
        asyncOpen(appId: appId, partitionValue: #function) { asyncOpenState in
            if case .waitingForUser = asyncOpenState {
                ex.fulfill()
            }
        }
    }

    // In case of no internet connection AsyncOpen should return an error if there is a timeout
    func testAsyncOpenFailWithoutInternetConnection() throws {
        let proxy = TimeoutProxyServer(port: 5678, targetPort: 9090)
        try! proxy.start()

        let appId = try! RealmServer.shared.createApp()
        let appConfig = AppConfiguration(baseURL: "http://localhost:5678",
                                         transport: AsyncOpenConnectionTimeoutTransport(),
                                         localAppName: nil,
                                         localAppVersion: nil)
        let app = App(id: appId, configuration: appConfig)
        _ = try logInUser(for: basicCredentials(app: app), app: app)

        proxy.delay = 3.0
        let ex = expectation(description: "download-realm-async-open-no-connection")
        asyncOpen(appId: appId, partitionValue: #function, timeout: 2000) { asyncOpenState in
            if case let .error(error) = asyncOpenState,
               let nsError = error as NSError? {
                XCTAssertEqual(nsError.code, Int(ETIMEDOUT))
                XCTAssertEqual(nsError.domain, NSPOSIXErrorDomain)
                ex.fulfill()
            }
        }
    }

    func testAsyncOpenProgressNotification() throws {
        let user = try logInUser(for: basicCredentials())
        if !isParent {
            populateRealm(user: user, partitionValue: #function)
            return
        }
        executeChild()

        let ex = expectation(description: "progress-async-open")
        asyncOpen(appId: appId, partitionValue: #function) { asyncOpenState in
            if case let .progress(progress) = asyncOpenState {
                XCTAssertTrue(progress.fractionCompleted > 0)
                if progress.isFinished {
                    ex.fulfill()
                }
            }
        }
    }

    // Cached App is already created on the setup of the test
    func testAsyncOpenWithACachedApp() throws {
        let user = try logInUser(for: basicCredentials())
        if !isParent {
            populateRealm(user: user, partitionValue: #function)
            return
        }
        executeChild()

        let ex = expectation(description: "download-cached-app-async-open")
        asyncOpen(partitionValue: #function) { asyncOpenState in
            if case let .open(realm) = asyncOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: SwiftSyncTestCase.bigObjectCount, realm, SwiftHugeSyncObject.self)
                ex.fulfill()
            }
        }
    }

    func testAsyncOpenThrowExceptionWithoutCachedApp() throws {
        resetAppCache()
        assertThrows(AsyncOpen(partitionValue: #function),
                     reason: "Cannot AsyncOpen the Realm because no appId was found. You must either explicitly pass an appId or initialize an App before displaying your View.")
    }

    func testAsyncOpenThrowExceptionWithoutMoreThanOneCachedApp() throws {
        let appId1 = try! RealmServer.shared.createApp()
        let appId2 = try! RealmServer.shared.createApp()
        _ = App(id: appId1)
        _ = App(id: appId2)
        assertThrows(AsyncOpen(partitionValue: #function),
                     reason: "Cannot AsyncOpen the Realm because more than one appId was found. When using multiple Apps you must explicitly pass an appId to indicate which to use.")
    }

    func testAsyncOpenWithDifferentPartitionValues() throws {
        let partitionValueA = #function
        let partitionValueB = "\(#function)bar"

        let user = try logInUser(for: basicCredentials())
        if !isParent {
            populateRealm(user: user, partitionValue: partitionValueA)
            return
        }
        executeChild()

        let ex = expectation(description: "download-partition-value-async-open")
        asyncOpen(partitionValue: partitionValueA) { asyncOpenState in
            if case let .open(realm) = asyncOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: SwiftSyncTestCase.bigObjectCount, realm, SwiftHugeSyncObject.self)
                ex.fulfill()
            }
        }

        let ex2 = expectation(description: "download-other-partition-value-async-open")
        asyncOpen(partitionValue: partitionValueB) { asyncOpenState in
            if case let .open(realm) = asyncOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: 0, realm, SwiftHugeSyncObject.self)
                ex2.fulfill()
            }
        }
    }

    func testAsyncOpenWithMultiUserApp() throws {
        let partitionValueA = #function
        let partitionValueB = "\(#function)bar"

        let syncUser1 = try logInUser(for: basicCredentials())
        let syncUser2 = try logInUser(for: basicCredentials())
        XCTAssertEqual(app.allUsers.count, 2)
        XCTAssertEqual(syncUser2.id, app.currentUser!.id)

        if !isParent {
            populateRealm(user: syncUser1, partitionValue: partitionValueA)
            return
        }
        executeChild()

        let ex = expectation(description: "test-multiuser1-app-async-open")
        asyncOpen(appId: appId, partitionValue: partitionValueB) { asyncOpenState in
            if case let .open(realm) = asyncOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: 0, realm, SwiftHugeSyncObject.self)
                ex.fulfill()
            }
        }

        app.switch(to: syncUser1)
        XCTAssertEqual(app.allUsers.count, 2)
        XCTAssertEqual(syncUser1.id, app.currentUser!.id)

        let ex2 = expectation(description: "test-multiuser2-app-async-open")
        asyncOpen(appId: appId, partitionValue: partitionValueA) { asyncOpenState in
            if case let .open(realm) = asyncOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: SwiftSyncTestCase.bigObjectCount, realm, SwiftHugeSyncObject.self)
                ex2.fulfill()
            }
        }
    }

    func testAsyncOpenWithUserAfterLogoutFromAnonymous() throws {
        let partitionValueA = #function
        let partitionValueB = "\(#function)bar"

        _ = try logInUser(for: .anonymous)
        let ex = expectation(description: "download-realm-anonymous-user-async-open")
        asyncOpen(appId: appId, partitionValue: partitionValueA) { asyncOpenState in
            if case let .open(realm) = asyncOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: 0, realm, SwiftHugeSyncObject.self)
                ex.fulfill()
            }
        }

        app.currentUser?.logOut { _ in } // Logout anonymous user

        let user = try logInUser(for: basicCredentials())
        if !isParent {
            populateRealm(user: user, partitionValue: partitionValueB)
            sleep(10)
            return
        }
        executeChild()

        let ex2 = expectation(description: "download-realm-after-logout-async-open")
        asyncOpen(appId: appId, partitionValue: partitionValueB) { asyncOpenState in
            if case let .open(realm) = asyncOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: SwiftSyncTestCase.bigObjectCount, realm, SwiftHugeSyncObject.self)
                ex2.fulfill()
            }
        }
    }

    // MARK: - AutoOpen
    func autoOpen(appId: String? = nil, partitionValue: String, timeout: UInt? = nil, handler: @escaping (AsyncOpenState) -> Void) {
        let autoOpen = AutoOpen(appId: appId, partitionValue: partitionValue, timeout: timeout)
        autoOpen.projectedValue
            .sink { autoOpenState in
                handler(autoOpenState)
            }
            .store(in: &cancellables)
        waitForExpectations(timeout: 10.0)
        autoOpen.cancel()
    }

    func testAutoOpenOpenRealm() throws {
        _ = try logInUser(for: basicCredentials())

        let ex = expectation(description: "download-realm-auto-open")
        autoOpen(appId: appId, partitionValue: #function) { autoOpenState in
            if case let .open(realm) = autoOpenState {
                XCTAssertNotNil(realm)
                ex.fulfill()
            }
        }
    }

    func testAutoOpenDownloadRealm() throws {
        let user = try logInUser(for: basicCredentials())

        if !isParent {
            populateRealm(user: user, partitionValue: #function)
            return
        }
        executeChild()

        let ex = expectation(description: "download-populated-realm-auto-open")
        autoOpen(appId: appId, partitionValue: #function) { autoOpenState in
            if case let .open(realm) = autoOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: SwiftSyncTestCase.bigObjectCount, realm, SwiftHugeSyncObject.self)
                ex.fulfill()
            }
        }
    }

    func testAutoOpenWaitingForUserWithoutUserLoggedIn() throws {
        let user = try logInUser(for: basicCredentials())
        user.logOut { _ in } //Logout current user

        let ex = expectation(description: "download-realm-auto-open-not-logged")
        autoOpen(appId: appId, partitionValue: #function) { autoOpenState in
            if case .waitingForUser = autoOpenState {
                ex.fulfill()
            }
        }
    }

    // In case of no internet connection AutoOpen should return an opened Realm, offline-first approach
    func testAutoOpenOpenRealmWithoutInternetConnection() throws {
        let proxy = TimeoutProxyServer(port: 5678, targetPort: 9090)
        try! proxy.start()

        let appId = try! RealmServer.shared.createApp()
        let appConfig = AppConfiguration(baseURL: "http://localhost:5678",
                                         transport: AsyncOpenConnectionTimeoutTransport(),
                                         localAppName: nil,
                                         localAppVersion: nil)
        let app = App(id: appId, configuration: appConfig)
        _ = try logInUser(for: basicCredentials(app: app), app: app)

        proxy.delay = 3.0
        let ex = expectation(description: "download-realm-auto-open-no-connection")
        autoOpen(appId: appId, partitionValue: #function, timeout: 2000) { autoOpenState in
            if case let .open(realm) = autoOpenState {
                XCTAssertNotNil(realm)
                ex.fulfill()
            }
        }

        proxy.stop()
    }

    func testAutoOpenProgressNotification() throws {
        let user = try logInUser(for: basicCredentials())
        if !isParent {
            populateRealm(user: user, partitionValue: #function)
            return
        }
        executeChild()

        let ex = expectation(description: "progress-auto-open")
        autoOpen(appId: appId, partitionValue: #function) { autoOpenState in
            if case let .progress(progress) = autoOpenState {
                XCTAssertTrue(progress.fractionCompleted > 0)
                if progress.isFinished {
                    ex.fulfill()
                }
            }
        }
    }

    // App is already created on the setup of the test
    func testAutoOpenWithACachedApp() throws {
        let user = try logInUser(for: basicCredentials())
        if !isParent {
            populateRealm(user: user, partitionValue: #function)
            return
        }
        executeChild()

        let ex = expectation(description: "download-cached-app-auto-open")
        autoOpen(partitionValue: #function) { autoOpenState in
            if case let .open(realm) = autoOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: SwiftSyncTestCase.bigObjectCount, realm, SwiftHugeSyncObject.self)
                ex.fulfill()
            }
        }
    }

    func testAutoOpenThrowExceptionWithoutCachedApp() throws {
        resetAppCache()
        assertThrows(AutoOpen(partitionValue: #function),
                     reason: "Cannot AsyncOpen the Realm because no appId was found. You must either explicitly pass an appId or initialize an App before displaying your View.")
    }

    func testAutoOpenThrowExceptionWithoutMoreThanOneCachedApp() throws {
        let appId1 = try! RealmServer.shared.createApp()
        let appId2 = try! RealmServer.shared.createApp()
        _ = App(id: appId1)
        _ = App(id: appId2)
        assertThrows(AutoOpen(partitionValue: #function),
                     reason: "Cannot AsyncOpen the Realm because more than one appId was found. When using multiple Apps you must explicitly pass an appId to indicate which to use.")
    }

    func testAutoOpenWithMultiUserApp() throws {
        let partitionValueA = #function
        let partitionValueB = "\(#function)bar"

        let syncUser1 = try logInUser(for: basicCredentials())
        let syncUser2 = try logInUser(for: basicCredentials())
        XCTAssertEqual(app.allUsers.count, 2)
        XCTAssertEqual(syncUser2.id, app.currentUser!.id)

        if !isParent {
            populateRealm(user: syncUser1, partitionValue: partitionValueA)
            return
        }
        executeChild()

        let ex = expectation(description: "test-multiuser1-app-auto-open")
        autoOpen(appId: appId, partitionValue: partitionValueB) { autoOpenState in
            if case let .open(realm) = autoOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: 0, realm, SwiftHugeSyncObject.self)
                ex.fulfill()
            }
        }

        app.switch(to: syncUser1)
        XCTAssertEqual(app.allUsers.count, 2)
        XCTAssertEqual(syncUser1.id, app.currentUser!.id)

        let ex2 = expectation(description: "test-multiuser2-app-auto-open")
        autoOpen(appId: appId, partitionValue: partitionValueA) { autoOpenState in
            if case let .open(realm) = autoOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: SwiftSyncTestCase.bigObjectCount, realm, SwiftHugeSyncObject.self)
                ex2.fulfill()
            }
        }
    }

    func testAutoOpenWithUserAfterLogoutFromAnonymous() throws {
        let partitionValueA = #function
        let partitionValueB = "\(#function)bar"

        _ = try logInUser(for: .anonymous)
        let ex = expectation(description: "download-realm-anonymous-user-auto-open")
        autoOpen(appId: appId, partitionValue: partitionValueA) { autoOpenState in
            if case let .open(realm) = autoOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: 0, realm, SwiftHugeSyncObject.self)
                ex.fulfill()
            }
        }

        app.currentUser?.logOut { _ in } // Logout anonymous user

        let user = try logInUser(for: basicCredentials())
        if !isParent {
            populateRealm(user: user, partitionValue: partitionValueB)
            sleep(10)
            return
        }
        executeChild()

        let ex2 = expectation(description: "download-realm-after-logout-auto-open")
        autoOpen(appId: appId, partitionValue: partitionValueB) { autoOpenState in
            if case let .open(realm) = autoOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: SwiftSyncTestCase.bigObjectCount, realm, SwiftHugeSyncObject.self)
                ex2.fulfill()
            }
        }
    }

    func testAutoOpenWithDifferentPartitionValues() throws {
        let partitionValueA = #function
        let partitionValueB = "\(#function)bar"

        let user = try logInUser(for: basicCredentials())
        if !isParent {
            populateRealm(user: user, partitionValue: partitionValueA)
            return
        }
        executeChild()

        let ex = expectation(description: "download-partition-value-auto-open")
        autoOpen(partitionValue: partitionValueA) { autoOpenState in
            if case let .open(realm) = autoOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: SwiftSyncTestCase.bigObjectCount, realm, SwiftHugeSyncObject.self)
                ex.fulfill()
            }
        }

        let ex2 = expectation(description: "download-other-partition-value-auto-open")
        autoOpen(partitionValue: partitionValueB) { autoOpenState in
            if case let .open(realm) = autoOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: 0, realm, SwiftHugeSyncObject.self)
                ex2.fulfill()
            }
        }
    }

    // MARK: - Mixed AsyncOpen & AutoOpen
    func testCombineAsyncOpenAutoOpenWithDifferentPartitionValues() throws {
        let partitionValueA = #function
        let partitionValueB = "\(#function)bar"

        let user = try logInUser(for: basicCredentials())
        if !isParent {
            populateRealm(user: user, partitionValue: partitionValueA)
            return
        }
        executeChild()

        let ex = expectation(description: "download-partition-value-async-open-mixed")
        asyncOpen(partitionValue: partitionValueA) { asyncOpenState in
            if case let .open(realm) = asyncOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: SwiftSyncTestCase.bigObjectCount, realm, SwiftHugeSyncObject.self)
                ex.fulfill()
            }
        }

        let ex2 = expectation(description: "download-partition-value-auto-open-mixed")
        autoOpen(partitionValue: partitionValueB) { autoOpenState in
            if case let .open(realm) = autoOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: 0, realm, SwiftHugeSyncObject.self)
                ex2.fulfill()
            }
        }
    }

    func testCombineAsyncOpenAutoOpenWithMultiUserApp() throws {
        let partitionValueA = #function
        let partitionValueB = "\(#function)bar"

        let syncUser1 = try logInUser(for: basicCredentials())
        let syncUser2 = try logInUser(for: basicCredentials())
        XCTAssertEqual(app.allUsers.count, 2)
        XCTAssertEqual(syncUser2.id, app.currentUser!.id)

        if !isParent {
            populateRealm(user: syncUser1, partitionValue: partitionValueA)
            return
        }
        executeChild()

        let ex = expectation(description: "test-combine-multiuser1-app-auto-open")
        autoOpen(appId: appId, partitionValue: partitionValueB) { autoOpenState in
            if case let .open(realm) = autoOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: 0, realm, SwiftHugeSyncObject.self)
                ex.fulfill()
            }
        }

        app.switch(to: syncUser1)
        XCTAssertEqual(app.allUsers.count, 2)
        XCTAssertEqual(syncUser1.id, app.currentUser!.id)

        let ex2 = expectation(description: "test-combine-multiuser2-app-auto-open")
        asyncOpen(appId: appId, partitionValue: partitionValueA) { asyncOpenState in
            if case let .open(realm) = asyncOpenState {
                XCTAssertNotNil(realm)
                self.checkCount(expected: SwiftSyncTestCase.bigObjectCount, realm, SwiftHugeSyncObject.self)
                ex2.fulfill()
            }
        }
    }
}
