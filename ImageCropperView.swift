import SwiftUI

// MARK: - Legacy Alias for Compatibility
typealias ImageCropperView = ModernImageCropperView

struct ModernImageCropperView: View {
    let image: UIImage
    var onCropped: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Transform States
    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    
    // MARK: - Gesture States
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1.0
    
    // MARK: - UI States
    @State private var showInstructions = true
    
    // MARK: - Constants
    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 3.0
    private let cropRatio: CGFloat = 1.0 // Square crop for FitSpo

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Image cropping area
                    GeometryReader { geometry in
                        let frameWidth = geometry.size.width
                        let frameHeight = frameWidth * cropRatio
                        
                        ZStack {
                            // Image container with gestures
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: frameWidth, height: frameHeight)
                                .offset(x: offset.width + dragOffset.width,
                                        y: offset.height + dragOffset.height)
                                .scaleEffect(scale * pinchScale)
                                .clipped()
                                .contentShape(Rectangle()) // Ensure the entire area is tappable
                                .gesture(
                                    SimultaneousGesture(
                                        DragGesture()
                                            .updating($dragOffset) { value, state, _ in
                                                state = value.translation
                                            }
                                            .onEnded { value in
                                                // Accumulate the offset
                                                offset.width += value.translation.width
                                                offset.height += value.translation.height
                                            },
                                        MagnificationGesture()
                                            .updating($pinchScale) { value, state, _ in
                                                state = value
                                            }
                                            .onEnded { value in
                                                // Accumulate the scale
                                                let newScale = scale * value
                                                scale = min(maxScale, max(minScale, newScale))
                                            }
                                    )
                                )
                            
                            // Crop overlay (non-interactive)
                            CropOverlay()
                                .allowsHitTesting(false) // This prevents the overlay from blocking gestures
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // Bottom controls
                    VStack(spacing: 24) {
                        // Instructions
                        if showInstructions {
                            VStack(spacing: 8) {
                                HStack(spacing: 16) {
                                    InstructionItem(
                                        icon: "hand.draw",
                                        text: "Drag to move"
                                    )
                                    
                                    InstructionItem(
                                        icon: "magnifyingglass",
                                        text: "Pinch to zoom"
                                    )
                                }
                                
                                Text("Perfect your photo for FitSpo")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.1))
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showInstructions = false
                                }
                            }
                        }
                        
                        // Action buttons
                        HStack(spacing: 16) {
                            // Reset button
                            Button(action: resetTransform) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Reset")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.2))
                                )
                            }
                            
                            // Next button
                            Button(action: {
                                if let cropped = cropImage() {
                                    onCropped(cropped)
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Text("Next")
                                        .font(.system(size: 16, weight: .semibold))
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.blue)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Crop Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
    
    private func resetTransform() {
        withAnimation(.easeInOut(duration: 0.3)) {
            offset = .zero
            scale = 1.0
        }
    }
    
    private func cropImage() -> UIImage? {
        // Get the current display scale
        let displayScale = scale * pinchScale
        let finalOffset = CGSize(
            width: offset.width + dragOffset.width,
            height: offset.height + dragOffset.height
        )
        
        // Debug: Print current values
        print("🔍 CROP DEBUG:")
        print("Image size: \(image.size)")
        print("Display scale: \(displayScale)")
        print("Final offset: \(finalOffset)")
        print("Scale: \(scale)")
        
        // The crop frame is always square and fills the width of the screen
        let screenWidth = UIScreen.main.bounds.width
        
        // Calculate how the image is displayed
        let imageAspectRatio = image.size.width / image.size.height
        let displayHeight = screenWidth / imageAspectRatio
        
        // Calculate the scale factors - this is where the issue was
        let scaleX = image.size.width / screenWidth
        let scaleY = image.size.height / displayHeight
        
        print("Screen width: \(screenWidth)")
        print("Display height: \(displayHeight)")
        print("Scale X: \(scaleX)")
        print("Scale Y: \(scaleY)")
        
        // NEW APPROACH: Calculate the crop area based on what's actually visible
        // The crop frame is a square that fills the screen width
        let cropFrameSize = screenWidth
        
        // Calculate the actual image area being displayed
        let imageDisplayWidth = screenWidth
        let imageDisplayHeight = displayHeight
        
        // Calculate the scale factor between display and actual image
        let displayToImageScale = image.size.width / imageDisplayWidth
        
        // Convert the offset from screen coordinates to image coordinates
        let imageOffsetX = finalOffset.width * displayToImageScale
        let imageOffsetY = finalOffset.height * displayToImageScale
        
        print("Image offset X: \(imageOffsetX)")
        print("Image offset Y: \(imageOffsetY)")
        
        // Calculate the crop rectangle
        // The crop frame is centered on the screen, so we need to find the center of the image
        let imageCenterX = image.size.width / 2
        let imageCenterY = image.size.height / 2
        
        // Calculate where the crop frame center is in image coordinates
        let cropCenterX = imageCenterX - imageOffsetX / displayScale
        let cropCenterY = imageCenterY - imageOffsetY / displayScale
        
        // Calculate the crop size in image coordinates
        let cropSizeInImage = cropFrameSize * displayToImageScale / displayScale
        
        // Calculate the crop rectangle
        let cropX = cropCenterX - cropSizeInImage / 2
        let cropY = cropCenterY - cropSizeInImage / 2
        
        print("Crop center X: \(cropCenterX)")
        print("Crop center Y: \(cropCenterY)")
        print("Crop size in image: \(cropSizeInImage)")
        print("Crop X: \(cropX)")
        print("Crop Y: \(cropY)")
        
        let cropRect = CGRect(
            x: max(0, cropX),
            y: max(0, cropY),
            width: min(cropSizeInImage, image.size.width - max(0, cropX)),
            height: min(cropSizeInImage, image.size.height - max(0, cropY))
        )
        
        print("Final crop rect: \(cropRect)")
        
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else { 
            print("❌ Failed to crop image")
            return nil 
        }
        
        let croppedImage = UIImage(cgImage: cgImage)
        print("✅ Cropped image size: \(croppedImage.size)")
        return croppedImage
    }
}

// MARK: - Crop Overlay
struct CropOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = width // Square crop
            
            ZStack {
                // Semi-transparent overlay
                Color.black.opacity(0.6)
                    .mask(
                        Rectangle()
                            .overlay(
                                Rectangle()
                                    .frame(width: width, height: height)
                                    .blendMode(.destinationOut)
                            )
                    )
                
                // Crop frame
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: width, height: height)
                
                // Grid lines (optional, for better composition)
                VStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { _ in
                        Divider()
                            .background(Color.white.opacity(0.3))
                            .frame(height: 1)
                        Spacer()
                    }
                }
                .frame(width: width, height: height)
                
                HStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { _ in
                        Divider()
                            .background(Color.white.opacity(0.3))
                            .frame(width: 1)
                        Spacer()
                    }
                }
                .frame(width: width, height: height)
            }
        }
    }
}

// MARK: - Instruction Item
struct InstructionItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}
