import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var bio         = ""
    @State private var avatarImage: UIImage?
    @State private var avatarURL   = ""      // existing URL
    @State private var showImagePicker = false
    @State private var isLoading       = false
    @State private var errorMessage    = ""
    @State private var showDeleteAlert = false

    private let db      = Firestore.firestore()
    private let storage = Storage.storage().reference()
    private var userId: String { Auth.auth().currentUser?.uid ?? "" }

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemGray6).opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Avatar Section
                        avatarSection
                        
                        // Profile Info Section
                        profileInfoSection
                        
                        // Action Buttons
                        actionButtonsSection
                        
                        Spacer(minLength: 50)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                
                // Loading overlay
                if isLoading {
                    loadingOverlay
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.black)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveProfile()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(displayName.isEmpty || isLoading ? .gray : .black)
                    .disabled(displayName.isEmpty || isLoading)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $avatarImage)
            }
            .alert("Remove Profile Picture?", isPresented: $showDeleteAlert) {
                Button("Remove", role: .destructive) {
                    removeAvatar()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove your current profile picture. You can add a new one anytime.")
            }
            .onAppear(perform: loadCurrentProfile)
        }
    }
    
    // MARK: - Avatar Section
    private var avatarSection: some View {
        VStack(spacing: 20) {
            Text("PROFILE PICTURE")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.2)
            
            ZStack {
                // Avatar image
                if let img = avatarImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.3), .pink.opacity(0.3), .orange.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                        )
                } else if let url = URL(string: avatarURL), !avatarURL.isEmpty {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable()
                               .scaledToFill()
                               .frame(width: 120, height: 120)
                               .clipShape(Circle())
                               .overlay(
                                   Circle()
                                       .stroke(
                                           LinearGradient(
                                               colors: [.purple.opacity(0.3), .pink.opacity(0.3), .orange.opacity(0.3)],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing
                                           ),
                                           lineWidth: 3
                                       )
                               )
                        } else {
                            placeholderAvatar
                        }
                    }
                } else {
                    placeholderAvatar
                }
                
                // Camera button overlay
                Button {
                    showImagePicker = true
                } label: {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                }
                .offset(x: 40, y: 40)
            }
            
            // Remove avatar button (only show if there's an avatar)
            if !avatarURL.isEmpty || avatarImage != nil {
                Button {
                    showDeleteAlert = true
                } label: {
                    Text("Remove Picture")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    private var placeholderAvatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(.systemGray5), Color(.systemGray4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 120, height: 120)
            .overlay(
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
            )
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .pink.opacity(0.3), .orange.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
            )
    }
    
    // MARK: - Profile Info Section
    private var profileInfoSection: some View {
        VStack(spacing: 24) {
            Text("PROFILE INFORMATION")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1.2)
            
            VStack(spacing: 20) {
                // Display Name Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display Name")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    TextField("Enter your name", text: $displayName)
                        .textFieldStyle(CustomTextFieldStyle())
                        .autocapitalization(.words)
                }
                
                // Bio Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bio")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    TextField("Tell us about yourself", text: $bio, axis: .vertical)
                        .textFieldStyle(CustomTextFieldStyle())
                        .lineLimit(3...6)
                }
            }
        }
    }
    
    // MARK: - Action Buttons Section
    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            if !errorMessage.isEmpty {
                errorBanner
            }
            
            // Save Button
            Button(action: saveProfile) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    
                    Text(isLoading ? "Saving..." : "Save Changes")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    LinearGradient(
                        colors: displayName.isEmpty ? [.gray] : [.black, .black.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(25)
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(displayName.isEmpty || isLoading)
        }
    }
    
    private var errorBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.orange)
            
            Text(errorMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            
            Spacer()
            
            Button {
                errorMessage = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                
                Text("Updating Profile...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6).opacity(0.9))
            )
        }
    }
    
    // MARK: - Helper Functions
    private func removeAvatar() {
        avatarImage = nil
        avatarURL = ""
    }

    private func loadCurrentProfile() {
        guard !userId.isEmpty else { return }
        db.collection("users").document(userId).getDocument { snap, err in
            if let err = err {
                errorMessage = err.localizedDescription
                return
            }
            let data = snap?.data() ?? [:]
            displayName = data["displayName"] as? String ?? ""
            bio         = data["bio"]         as? String ?? ""
            avatarURL   = data["avatarURL"]   as? String ?? ""
        }
    }

    private func saveProfile() {
        guard !userId.isEmpty else { return }
        isLoading    = true
        errorMessage = ""

        // 1) If user picked a new image, upload it first
        if let newImage = avatarImage,
           let jpegData = newImage.jpegData(compressionQuality: 0.8) {
            let ref = storage.child("avatars/\(userId).jpg")
            ref.putData(jpegData, metadata: nil) { _, err in
                if let err = err {
                    fail(err.localizedDescription)
                } else {
                    ref.downloadURL { url, err in
                        if let err = err {
                            fail(err.localizedDescription)
                        } else {
                            updateUserDoc(avatarURL: url?.absoluteString)
                        }
                    }
                }
            }
        } else {
            // 2) No new avatar, just update text fields
            updateUserDoc(avatarURL: avatarURL)
        }
    }

    private func updateUserDoc(avatarURL: String?) {
        var data: [String: Any] = [
            "displayName": displayName,
            "bio":         bio
        ]
        if let avatarURL = avatarURL {
            data["avatarURL"] = avatarURL
        }

        db.collection("users").document(userId).updateData(data) { err in
            if let err = err {
                fail(err.localizedDescription)
            } else {
                isLoading = false
                dismiss()
            }
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        isLoading    = false
    }
}

// MARK: - Custom TextField Style
struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
    }
}
