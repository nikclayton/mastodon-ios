//
//  NotificationTimelineViewModel.swift
//  Mastodon
//
//  Created by MainasuK on 2022-1-21.
//

import UIKit
import Combine
import CoreDataStack
import GameplayKit
import MastodonSDK
import MastodonCore

final class NotificationTimelineViewModel {
    
    var disposeBag = Set<AnyCancellable>()
    
    // input
    let context: AppContext
    let authContext: AuthContext
    let scope: Scope
    let dataController: FeedDataController
    @Published var isLoadingLatest = false
    @Published var lastAutomaticFetchTimestamp: Date?
    
    // output
    var diffableDataSource: UITableViewDiffableDataSource<NotificationSection, NotificationItem>?
    var didLoadLatest = PassthroughSubject<Void, Never>()

    // bottom loader
    private(set) lazy var loadOldestStateMachine: GKStateMachine = {
        // exclude timeline middle fetcher state
        let stateMachine = GKStateMachine(states: [
            LoadOldestState.Initial(viewModel: self),
            LoadOldestState.Loading(viewModel: self),
            LoadOldestState.Fail(viewModel: self),
            LoadOldestState.Idle(viewModel: self),
            LoadOldestState.NoMore(viewModel: self),
        ])
        stateMachine.enter(LoadOldestState.Initial.self)
        return stateMachine
    }()
    
    @MainActor
    init(
        context: AppContext,
        authContext: AuthContext,
        scope: Scope
    ) {
        self.context = context
        self.authContext = authContext
        self.scope = scope
        self.dataController = FeedDataController(context: context, authContext: authContext)

        switch scope {
        case .everything:
            self.dataController.records = (try? FileManager.default.cachedNotificationsAll(for: authContext.mastodonAuthenticationBox))?.map({ notification in
                MastodonFeed.fromNotification(notification, relationship: nil, kind: .notificationAll)
            }) ?? []
        case .mentions:
            self.dataController.records = (try? FileManager.default.cachedNotificationsMentions(for: authContext.mastodonAuthenticationBox))?.map({ notification in
                MastodonFeed.fromNotification(notification, relationship: nil, kind: .notificationMentions)
            }) ?? []
        }

        self.dataController.$records
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { feeds in
                let items: [Mastodon.Entity.Notification] = feeds.compactMap { feed -> Mastodon.Entity.Notification? in
                    guard let status = feed.notification else { return nil }
                    return status
                }
                switch self.scope {
                case .everything:
                    FileManager.default.cacheNotificationsAll(items: items, for: authContext.mastodonAuthenticationBox)
                case .mentions:
                    FileManager.default.cacheNotificationsMentions(items: items, for: authContext.mastodonAuthenticationBox)
                }
            })
            .store(in: &disposeBag)
    }
    
    
}

extension NotificationTimelineViewModel {

    typealias Scope = APIService.MastodonNotificationScope

}

extension NotificationTimelineViewModel {
    
    // load lastest
    func loadLatest() async {
        isLoadingLatest = true
        defer { isLoadingLatest = false }
        
        switch scope {
        case .everything:
            dataController.loadInitial(kind: .notificationAll)
        case .mentions:
            dataController.loadInitial(kind: .notificationMentions)
        }

        didLoadLatest.send()
    }
    
    // load timeline gap
    func loadMore(item: NotificationItem) async {
        switch scope {
        case .everything:
            dataController.loadNext(kind: .notificationAll)
        case .mentions:
            dataController.loadNext(kind: .notificationMentions)
        }
    }
}
