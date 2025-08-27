//
//  NewPostView.swift
//  FitSpo
//
//  Modern Instagram-style image selector with enhanced UX
//  Features: Smooth animations, better grid layout, improved preview, modern styling

import SwiftUI
import PhotosUI

private struct OffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct NewPostView: View {
    
    // MARK: - PhotoKit
    @State private var assets: [PHAsset] = []
    @State private var isLoadingAssets = true
    private let manager = PHCachingImageManager()
    
    // MARK: - Selection
    @State private var selected: PHAsset?
    @State private var preview: UIImage?
    @State private var collapsed = false
    @State private var showCropper = false
    @State private var showCaption = false
    
    // MARK: - UI States
    @State private var showPermissionAlert = false
    @State private var permissionDenied = false
    
    // MARK: - Location
    @StateObject private var locationManager = LocationManager.shared
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // MARK: - Preview Section
                    previewSection
                    
                    // MARK: - Library Header
                    libraryHeader
                    
                    // MARK: - Photo Grid
                    photoGrid
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Next") {
                        showCropper = true
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(preview != nil ? .blue : .secondary)
                    .disabled(preview == nil)
                }
            }
            .sheet(isPresented: $showCropper) {
                if let img = preview {
                    ModernImageCropperView(image: img) { croppedImage in
                        preview = croppedImage
                        showCropper = false
                        showCaption = true
                    }
                }
            }
            .background(
                NavigationLink(isActive: $showCaption) {
                    if let img = preview {
                        PostCaptionView(image: img) {
                            dismiss()
                        }
                    }
                } label: { EmptyView() }.hidden()
            )
            .alert("Photo Library Access", isPresented: $showPermissionAlert) {
                Button("Settings") {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Please allow access to your photo library to select photos for your post.")
            }
            .task(loadAssets)
            .coordinateSpace(name: "scroll")
        }
    }
    
    // MARK: - Preview Section
    private var previewSection: some View {
        Group {
            if let img = preview {
                ZStack(alignment: .bottomTrailing) {
                    // Instagram-style photo display
                    GeometryReader { geometry in
                        let screenWidth = geometry.size.width
                        let imageAspectRatio = img.size.width / img.size.height
                        
                        // Instagram logic: if image is wider than 4:5, center it and crop sides
                        // If image is taller than 4:5, let it fill width and crop top/bottom
                        let maxAspectRatio: CGFloat = 0.8 // 4:5 ratio
                        
                        if imageAspectRatio > maxAspectRatio {
                            // Wide image: fill width and crop sides (like Instagram)
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: screenWidth, height: screenWidth / maxAspectRatio)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        } else {
                            // Tall/normal image: fill width and crop top/bottom
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: screenWidth, height: screenWidth / imageAspectRatio)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        }
                    }
                    .frame(maxHeight: collapsed ? 0 : 450)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    
                    // Crop button overlay
                    Button(action: {
                        showCropper = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "crop")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Crop")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(20)
                    }
                    .padding(16)
                }
            } else {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Select a photo to get started")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: collapsed ? 0 : 450)
                .background(Color(.systemGray6))
                .cornerRadius(16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.3), value: collapsed)
        .animation(.easeInOut(duration: 0.3), value: preview)
        
        // Collapse indicator
        .overlay(alignment: .top) {
            if collapsed && preview != nil {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        collapsed = false
                    }
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: "chevron.compact.up")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Text("Tap to expand")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
    
    // MARK: - Library Header
    private var libraryHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Photo Library")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 4) {
                    Text("\(assets.count) photos")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    if selected != nil {
                        Text("• Selected")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
            
            if isLoadingAssets {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: collapsed ? 0 : nil)
        .clipped()
        .opacity(collapsed ? 0 : 1)
        .animation(.easeInOut(duration: 0.3), value: collapsed)
    }
    
    // MARK: - Photo Grid
    private var photoGrid: some View {
        ScrollView {
            GeometryReader { geo in
                Color.clear
                    .preference(key: OffsetKey.self,
                               value: geo.frame(in: .named("scroll")).minY)
            }
            .frame(height: 0)
            
            if assets.isEmpty && !isLoadingAssets {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No photos found")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    if permissionDenied {
                        Button("Open Settings") {
                            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsUrl)
                            }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)
                    }
                }
                .padding(.top, 60)
            } else {
                // Fixed grid layout with proper spacing
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2)
                ], spacing: 2) {
                    ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                        FixedSizeThumbnail(
                            asset: asset,
                            manager: manager,
                            isSelected: asset == selected,
                            index: index
                        ) {
                            print("Tapped thumbnail at index: \(index)")
                            select(asset)
                        }
                        .id("\(asset.localIdentifier)-\(index)")
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .background(Color(.systemGray6))
        .onPreferenceChange(OffsetKey.self) { y in
            if y < -30 && !collapsed && preview != nil {
                withAnimation(.easeInOut(duration: 0.3)) {
                    collapsed = true
                }
            } else if y > 0 && collapsed {
                withAnimation(.easeInOut(duration: 0.3)) {
                    collapsed = false
                }
            }
        }
    }
    
    // MARK: - PhotoKit Loading
    private func loadAssets() async {
        isLoadingAssets = true
        
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if granted != .authorized && granted != .limited {
                permissionDenied = true
                isLoadingAssets = false
                return
            }
        case .denied, .restricted:
            permissionDenied = true
            isLoadingAssets = false
            return
        case .authorized, .limited:
            break
        @unknown default:
            permissionDenied = true
            isLoadingAssets = false
            return
        }
        
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 100 // Increased limit for better experience
        
        let fetch = PHAsset.fetchAssets(with: .image, options: options)
        
        var tempAssets: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in
            tempAssets.append(asset)
        }
        
        await MainActor.run {
            assets = tempAssets
            isLoadingAssets = false
            
            // Auto-select first image
            if let first = assets.first {
                select(first)
            }
        }
    }
    
    // MARK: - Selection
    private func select(_ asset: PHAsset) {
        // Haptic feedback for selection
        let selectionFeedback = UISelectionFeedbackGenerator()
        selectionFeedback.selectionChanged()
        
        // Debug: Print asset info to help track selection
        print("Selected asset: \(asset.localIdentifier)")
        
        selected = asset
        collapsed = false
        
        let size = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        manager.requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                preview = image
            }
        }
    }
}

// MARK: - Fixed Size Thumbnail
fileprivate struct FixedSizeThumbnail: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    let isSelected: Bool
    let index: Int
    let onTap: () -> Void
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var isPressed = false
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            
            ZStack {
                // Background to ensure consistent sizing
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: size, height: size)
                
                // Image or placeholder
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: size, height: size)
                        .overlay(
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "photo")
                                        .font(.system(size: 20))
                                        .foregroundColor(.secondary)
                                }
                            }
                        )
                }
                
                // Selection indicator
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                
                // Press state overlay
                if isPressed {
                    Rectangle()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: size, height: size)
                }
            }
            .frame(width: size, height: size)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .contentShape(Rectangle()) // Ensures the entire rectangle is tappable
            .onTapGesture {
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                
                withAnimation(.easeInOut(duration: 0.2)) {
                    onTap()
                }
            }
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            }, perform: {})
        }
        .aspectRatio(1, contentMode: .fit) // Force square aspect ratio
        .onAppear(perform: loadThumbnail)
    }
    
    private func loadThumbnail() {
        guard image == nil else { return }
        
        isLoading = true
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat // Use fast format for thumbnails
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        // Calculate proper thumbnail size based on screen density
        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: 200 * scale, height: 200 * scale) // Optimized for performance
        
        manager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { img, info in
            DispatchQueue.main.async {
                // Only update if this is still the current asset
                if let img = img {
                    image = img
                }
                isLoading = false
            }
        }
    }
}
