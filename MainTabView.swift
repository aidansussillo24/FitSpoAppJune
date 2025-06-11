//  Replace file: MainTabView.swift
//  FitSpo
//
//  Updates the Profile tab to call `ProfileView()` with no arguments
//  (ProfileView now defaults to the current user internally).

import SwiftUI
import FirebaseAuth

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            ExploreView()
                .tabItem { Label("Explore", systemImage: "magnifyingglass") }

            NewPostView()
                .tabItem { Label("Post", systemImage: "plus.app") }

            MapView()
                .tabItem { Label("Map", systemImage: "map") }

            ProfileView()              // ← no arguments needed
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

//  End of file
