//
//  PlaceholderView.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import SwiftUI

struct PlaceholderView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title)
                .fontWeight(.bold)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
