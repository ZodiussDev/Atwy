//
//  ChannelDetailsView.swift
//  Atwy
//
//  Created by Antoine Bollengier on 28.12.22.
//

import SwiftUI
import InfiniteScrollViews
import YouTubeKit

struct ChannelDetailsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State var channel: YTLittleChannelInfos
    @State var navigationTitle: String = ""
    @StateObject private var model = Model()
    @State private var needToReload: Bool = true
    @State private var selectedMode: Int = 0
    @State private var selectedCategory: ChannelInfosResponse.RequestTypes? = .videos
    @State private var shouldReloadScrollView: Bool = false
    @State private var scrollPosition: CGPoint = .zero
    @State private var isChangingSubscriptionStatus: Bool = false
    private let changeIndex: Int = 0
    @ObservedObject private var APIM = APIKeyModel.shared
    @ObservedObject private var VPM = VideoPlayerModel.shared
    @ObservedObject private var network = NetworkReachabilityModel.shared
    var body: some View {
        GeometryReader { mainGeometry in
            ZStack {
                if model.isFetchingChannelInfos {
                    HStack(alignment: .center) {
                        Spacer()
                        LoadingView()
                        Spacer()
                    }
                }
                VStack {
                    if let channelInfos = model.channelInfos {
                        LazyVStack {
                            VStack {
                                ZStack(alignment: .center) {
                                    ChannelBannerRectangleView(channelBannerURL: channelInfos.bannerThumbnails.last?.url)
                                    ChannelAvatarCircleView(avatarURL: channelInfos.avatarThumbnails[(channelInfos.avatarThumbnails.lastIndex(where: {_ in true})) ?? 1 - 1].url)
                                        .offset(x: (scrollPosition.y < 0) ? (scrollPosition.y < -150) ? mainGeometry.size.width * 0.3 : scrollPosition.y / 150 * mainGeometry.size.width * 0.3 : 0, y: (scrollPosition.y < 0) ? (scrollPosition.y < -150) ? -150 : -scrollPosition.y : 0)
                                }
                                Text(channelInfos.name ?? "")
                                    .font(.title)
                                    .bold()
                            }
                            .frame(height: 150)
                            .onAppear {
                                navigationTitle = ""
                            }
                            .onDisappear {
                                navigationTitle = channelInfos.name ?? ""
                            }
                        }
                        HStack {
                            Text(channelInfos.publicIdentifier ?? "")
                            if channelInfos.publicIdentifier != nil, channelInfos.subscribersCount != nil {
                                Text(" • ")
                            }
                            Text(channelInfos.subscribersCount ?? "")
                            if channelInfos.subscribersCount != nil, channelInfos.videosCount != nil {
                                Text(" • ")
                            }
                            Text(channelInfos.videosCount ?? "")
                        }
                        .padding(.top)
                        .font(.system(size: 12))
                        .bold()
                        .opacity(0.5)
                        if channelInfos.isSubcribeButtonEnabled == true, let subscribeStatus = channelInfos.subscribeStatus {
                            Button {
                                Task {
                                    DispatchQueue.main.async {
                                        self.isChangingSubscriptionStatus = true
                                    }
                                    var error: (any Error)?
                                    if subscribeStatus {
                                        error = await channel.unsubscribe(youtubeModel: YTM)
                                    } else {
                                        error = await channel.subscribe(youtubeModel: YTM)
                                    }
                                    DispatchQueue.main.async {
                                        if error == nil {
                                            withAnimation {
                                                model.channelInfos?.subscribeStatus?.toggle()
                                            }
                                        }
                                        self.isChangingSubscriptionStatus = false
                                    }
                                }
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 5)
                                        .foregroundStyle(subscribeStatus ? .white : .red)
                                    Text(subscribeStatus ? "Subscribed" : "Subscribe")
                                        .foregroundStyle(subscribeStatus ? .red : .white)
                                        .font(.callout)
                                }
                                .frame(width: 100, height: 35)
                            }
                            .disabled(isChangingSubscriptionStatus)
                        }
                        Divider()
                        Picker("", selection: $selectedMode, content: {
                            if model.channelInfos?.requestParams[.videos] != nil {
                                Text("Videos").tag(0)
                            }
                            if model.channelInfos?.requestParams[.shorts] != nil {
                                Text("Shorts").tag(1)
                            }
                            if model.channelInfos?.requestParams[.directs] != nil {
                                Text("Directs").tag(2)
                            }
                            if model.channelInfos?.requestParams[.playlists] != nil {
                                Text("Playlists").tag(3)
                            }
                        })
                        .pickerStyle(.segmented)
                        // only for iOS 17
//                        .onChange(of: selectedMode, initial: true, {
//                            selectedCategory = getCategoryForTabIndex(selectedMode)
//                            guard let newValueCategory = selectedCategory else { selectedMode = 0; selectedCategory = .videos ; return }
//                            if (model.channelInfos?.channelContentStore[newValueCategory] as? (any ListableChannelContent)) == nil {
//                                model.fetchCategoryContents(for: newValueCategory)
//                            }
//                        })
                        .onChange(of: selectedMode, perform: { _ in
                            selectedCategory = getCategoryForTabIndex(selectedMode)
                            guard let newValueCategory = selectedCategory else { selectedMode = 0; selectedCategory = .videos ; return }
                            if (model.channelInfos?.channelContentStore[newValueCategory] as? (any ListableChannelContent)) == nil {
                                model.fetchCategoryContents(for: newValueCategory)
                            }
                        })
                        if let selectedCategory = selectedCategory {
                            if model.fetchingStates[selectedCategory] == true {
                                LoadingView()
                            } else {
                                if model.channelInfos?.channelContentStore[selectedCategory] as? (any ListableChannelContent) != nil {
                                    let itemsBinding = Binding(get: {
                                        return (model.channelInfos?.channelContentStore[selectedCategory] as? (any ListableChannelContent))?.items ?? []
                                    }, set: { newValue in
                                        var itemsContents = model.channelInfos?.channelContentStore[selectedCategory] as? (any ListableChannelContent)
                                        itemsContents?.items = newValue
                                        model.channelInfos?.channelContentStore[selectedCategory] = itemsContents
                                    })
                                    if itemsBinding.wrappedValue.isEmpty {
                                        VStack(alignment: .center) {
                                            Spacer()
                                            Text("No items in this category.")
                                            Spacer()
                                        }
                                    } else {
                                        ElementsInfiniteScrollView(
                                            items: itemsBinding,
                                            shouldReloadScrollView: $shouldReloadScrollView,
                                            fetchMoreResultsAction: {
                                                if !(model.fetchingStates[selectedCategory] ?? false) {
                                                    model.fetchContentsContinuation(for: selectedCategory)
                                                }
                                            }
                                        )
                                        .frame(width: mainGeometry.size.width, height: mainGeometry.size.height * 0.7 - 49) // 49 for the navigation bar
                                        .id(selectedCategory)
                                    }
                                } else {
                                    VStack(alignment: .center) {
                                        Spacer()
                                        Text("No items in this category.")
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }
                .onAppear {
                    if needToReload {
                        model.fetchInfos(channel: channel, {
                            model.fetchCategoryContents(for: .videos)
                        })
                        needToReload = false
                    }
                }
#if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .navigationTitle(navigationTitle)
                .toolbar(content: {
#if os(macOS)
                    ToolbarItem(placement: .secondaryAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
#else
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
#endif
                })
                .navigationBarBackButtonHidden(true)
                .customNavigationTitleWithRightIcon {
                    ShowSettingsButtonView()
                }
                //        .toolbar(content: {
                //            ShareChannelView(channelID: channelID)
                //        })
                .observeScrollPosition(displayIndicator: false, scrollChanged: { scrollPosition in
                    self.scrollPosition = scrollPosition
                })
                .scrollDisabled(true)
            }
        }
    }
    
    private func getCategoryForTabIndex(_ tabIndex: Int) -> ChannelInfosResponse.RequestTypes? {
        switch tabIndex {
        case 0:
            return .videos
        case 1:
            return .shorts
        case 2:
            return .directs
        case 3:
            return .playlists
        default:
            return nil
        }
    }
    
    private class Model: ObservableObject {
        @Published var channelInfos: ChannelInfosResponse?
        
        @Published var isFetchingChannelInfos: Bool = false
        
        @Published var fetchingStates: [ChannelInfosResponse.RequestTypes : Bool] = [:]
        
        @Published var continuationsFetchingStates: [ChannelInfosResponse.RequestTypes : Bool] = [:]
        
        private var channel: YTLittleChannelInfos?
            
        public func fetchInfos(channel: YTLittleChannelInfos, _ end: (() -> Void)? = nil) {
            self.channel = channel
            DispatchQueue.main.async {
                self.isFetchingChannelInfos = true
                self.channelInfos = nil
            }
            ChannelInfosResponse.sendRequest(youtubeModel: YTM, data: [.browseId: channel.channelId], result: { response, error in
                DispatchQueue.main.async {
                    self.channelInfos = response
                    self.isFetchingChannelInfos = false
                    end?()
                }
                if let error = error {
                    print("Couldn't fetch channel infos: \(error.localizedDescription)")
                }
            })
        }
        
        public func fetchCategoryContents(for category: ChannelInfosResponse.RequestTypes) {
            if let channelId = self.channel?.channelId, let requestParams = self.channelInfos?.requestParams[category] {
                DispatchQueue.main.async {
                    self.channelInfos?.channelContentStore.removeValue(forKey: category)
                    self.fetchingStates[category] = true
                }
                ChannelInfosResponse.sendRequest(youtubeModel: YTM, data: [.browseId: channelId, .params: requestParams], result: { response, error in
                    DispatchQueue.main.async {
                        self.fetchingStates[category] = false
                        self.channelInfos?.channelContentStore[category] = response?.currentContent
                        self.channelInfos?.channelContentContinuationStore[category] = response?.channelContentContinuationStore[category]
                    }
                    if let error = error {
                        print("Error while fetching \(category): \(error.localizedDescription)")
                    }
                })
            }
        }
        
        public func fetchContentsContinuation(for category: ChannelInfosResponse.RequestTypes) {
            if let channelInfos = self.channelInfos, (channelInfos.channelContentContinuationStore[category] ?? nil) != nil {
                DispatchQueue.main.async {
                    self.continuationsFetchingStates[category] = true
                }
                                
                switch category {
                case .directs:
                    channelInfos.getChannelContentContinuation(ChannelInfosResponse.Directs.self, youtubeModel: YTM, result: { response, error in
                        if let response = response {
                            DispatchQueue.main.async {
                                self.channelInfos?.mergeListableChannelContentContinuation(response)
                            }
                        }
                        if let error = error {
                            print("Error while fetching \(category): \(error.localizedDescription)")
                        }
                    })
                case .playlists:
                    channelInfos.getChannelContentContinuation(ChannelInfosResponse.Playlists.self, youtubeModel: YTM, result: { response, error in
                        if let response = response {
                            DispatchQueue.main.async {
                                self.channelInfos?.mergeListableChannelContentContinuation(response)
                            }
                        }
                        if let error = error {
                            print("Error while fetching \(category): \(error.localizedDescription)")
                        }
                    })
                case .shorts:
                    channelInfos.getChannelContentContinuation(ChannelInfosResponse.Shorts.self, youtubeModel: YTM, result: { response, error in
                        if let response = response {
                            DispatchQueue.main.async {
                                self.channelInfos?.mergeListableChannelContentContinuation(response)
                            }
                        }
                        if let error = error {
                            print("Error while fetching \(category): \(error.localizedDescription)")
                        }
                    })
                case .videos:
                    channelInfos.getChannelContentContinuation(ChannelInfosResponse.Videos.self, youtubeModel: YTM, result: { response, error in
                        if let response = response {
                            DispatchQueue.main.async {
                                self.channelInfos?.mergeListableChannelContentContinuation(response)
                            }
                        }
                        if let error = error {
                            print("Error while fetching \(category): \(error.localizedDescription)")
                        }
                    })
                default:
                    break
                }
            }
            
            func getChannelContinuationContentTypeFor(category: ChannelInfosResponse.RequestTypes) -> (any ChannelContent.Type)? {
                switch category {
                case .directs:
                    return ChannelInfosResponse.Directs.self
                case .playlists:
                    return ChannelInfosResponse.Playlists.self
                case .shorts:
                    return ChannelInfosResponse.Shorts.self
                case .videos:
                    return ChannelInfosResponse.Videos.self
                default:
                    return nil
                }
            }
        }
    }
}
