//
//  OutfitItem.swift
//  FitSpo
//
//  Model returned by the Cloud Function `scanOutfit`.
//

import Foundation

struct OutfitItem: Identifiable, Decodable {
    let id      : String
    let label   : String
    let brand   : String
    let shopURL : String
    /// If you later return thumbnails, add:
    /// let imageURL: String
}
