//
//  OutfitItemSheet.swift
//  FitSpo
//
//  Bottom-sheet UI for displaying detected clothing items.
//

import SwiftUI

struct OutfitItemSheet: View {
    let items: [OutfitItem]
    let isScanning: Bool
    @Binding var isPresented: Bool

    // safari presentation
    @State private var safariURL: URL? = nil

    var body: some View {
        NavigationStack {
            Group {
                if isScanning {
                    VStack(spacing: 16) {
                        ProgressView("Scanning…").progressViewStyle(.circular)
                        Text("Looking for items in the photo")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "questionmark.square.dashed")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No items detected")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(items) { item in
                            Button {
                                if let url = URL(string: item.shopURL) {
                                    safariURL = url
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    // thumbnail placeholder – uncomment if you return imageURL
                                    // AsyncImage(url: URL(string: item.imageURL)) { img in
                                    //     img.resizable().scaledToFill()
                                    // } placeholder: {
                                    //     Color.gray.opacity(0.2)
                                    // }
                                    // .frame(width: 44, height: 44)
                                    // .clipShape(RoundedRectangle(cornerRadius: 6))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.label)
                                            .font(.body.bold())
                                        if !item.brand.isEmpty {
                                            Text(item.brand)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Outfit items")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
            .sheet(item: $safariURL) { url in
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }
}
