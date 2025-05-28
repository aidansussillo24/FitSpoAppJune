import SwiftUI
import FirebaseAuth

struct MainTabView: View {
    // 0=Home, 1=Explore, 2=Post, 3=Map, 4=Profile
    @State private var selection = 0
    @State private var showNewPost = false

    // Grab your own UID once
    private var myUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    var body: some View {
        TabView(selection: $selection) {
            // Home
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            // Explore
            ExploreView()
                .tabItem { Label("Explore", systemImage: "magnifyingglass") }
                .tag(1)

            // Post (dummy “+”)
            Color.clear
                .tabItem { Label("Post", systemImage: "plus.circle.fill") }
                .tag(2)
                .onAppear { showNewPost = true }

            // Map
            MapView()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(3)

            // Profile (pass in your UID)
            ProfileView(userId: myUserId)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(4)
        }
        // When you tap “+”, present NewPostView
        .sheet(isPresented: $showNewPost, onDismiss: {
            selection = 0
        }) {
            NewPostView()
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
