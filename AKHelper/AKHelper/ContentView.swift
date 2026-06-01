//
//  ContentView.swift
//  AKHelper
//
//  Created on 2026/6/1.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)

                NavigationLink {
                    CameraView()
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("实时摄像头")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("打开摄像头", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(32)
            .navigationTitle("AKHelper")
        }
    }
}

#Preview {
    ContentView()
}
