//
//  DailyDuasView.swift
//  Groo
//
//  Sheet wrapper for daily supplications, reusing EssentialRecitationsView.
//

import SwiftUI

struct DailyDuasSheet: View {
    @State private var expandedId: String?
    @Environment(\.dismiss) private var dismiss

    private var audioService: RecitationAudioService { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                EssentialRecitationsView(
                    recitations: PrayerGuideDataProvider.dailyDuas(),
                    expandedId: $expandedId,
                    audioService: audioService
                )
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Daily Duas")
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        audioService.stop()
                        dismiss()
                    }
                }
            }
        }
    }
}
