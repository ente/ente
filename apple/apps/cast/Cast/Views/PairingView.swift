import SwiftUI
import UIKit

struct PairingView: View {
    let deviceCode: String
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // White background
                Color.white
                    .ignoresSafeArea()
                
                // Main content - card positioned with custom padding
                HStack(spacing: 0) {
                    // Left padding (1x)
                    Spacer()
                        .frame(width: geometry.size.width * 0.05)
                    
                    // Green card with content
                    ZStack {
                        // Green card background
                        RoundedRectangle(cornerRadius: 36)
                            .fill(Color(red: 0/255, green: 179/255, blue: 61/255))
                            .shadow(color: Color.black.opacity(0.25), radius: 4, y: 4)
                        
                        // Card content
                        VStack(spacing: 0) {
                            // Title section
                            VStack(spacing: -5) {
                                Text("Ready to")
                                    .font(FontUtils.montserratExtraBold(size: geometry.size.width * 0.035))
                                    .foregroundColor(.white)
                                
                                Text("Connect?")
                                    .font(FontUtils.montserratExtraBold(size: geometry.size.width * 0.065))
                                    .foregroundColor(.white)
                            }
                            .padding(.top, geometry.size.height * 0.06)
                            
                            Spacer()
                                .frame(height: geometry.size.height * 0.05)
                            
                            // Pairing code box
                            ZStack {
                                // Reserve the 6-char code footprint so the box doesn't resize when the code arrives
                                Text(deviceCode.isEmpty ? "000000" : deviceCode)
                                    .font(.system(size: geometry.size.width * 0.09, weight: .heavy, design: .monospaced))
                                    .tracking(geometry.size.width * 0.015)
                                    .opacity(0)

                                if deviceCode.isEmpty {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                        .scaleEffect(1.8)
                                } else {
                                    Text(deviceCode)
                                        .font(.system(size: geometry.size.width * 0.09, weight: .heavy, design: .monospaced))
                                        .tracking(geometry.size.width * 0.015)
                                        .foregroundColor(.white)
                                        .scaleEffect(pulseScale)
                                }
                            }
                            .padding(.horizontal, geometry.size.width * 0.04)
                            .padding(.vertical, geometry.size.height * 0.025)
                            .background(
                                RoundedRectangle(cornerRadius: 32)
                                    .fill(Color(red: 0/255, green: 150/255, blue: 51/255))
                            )
                            
                            Spacer()
                                .frame(height: geometry.size.height * 0.08)
                            
                            // Instruction steps
                            HStack(spacing: geometry.size.width * 0.05) {
                                InstructionStep(
                                    number: "1",
                                    text: "Open any album",
                                    icon: "photo.on.rectangle.angled",
                                    geometry: geometry
                                )
                                
                                InstructionStep(
                                    number: "2",
                                    text: "Click Cast button",
                                    icon: "tv",
                                    geometry: geometry
                                )
                                
                                InstructionStep(
                                    number: "3",
                                    text: "Enter the code",
                                    icon: "keyboard",
                                    geometry: geometry
                                )
                            }
                            
                            Spacer()
                                .frame(height: geometry.size.height * 0.06)
                            
                            // Help text
                            Text("Visit ente.com/cast for help")
                                .font(FontUtils.interMedium(size: geometry.size.width * 0.012))
                                .foregroundColor(.white)
                            
                            Spacer()
                                .frame(height: geometry.size.height * 0.04)
                        }
                        
                        // Ducky positioned at bottom right of the card
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image("ducky_camera")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: geometry.size.width * 0.27,
                                           height: geometry.size.width * 0.27)
                                    .offset(x: geometry.size.width * 0.18,
                                            y: geometry.size.height * 0.18)
                            }
                        }
                    }
                    .frame(width: geometry.size.width * 0.8,
                           height: geometry.size.height * 0.85)
                    
                    // Right padding (3x)
                    Spacer()
                        .frame(width: geometry.size.width * 0.15)
                }
                .padding(.top, geometry.size.height * 0.05) // Top padding (1x)
                .padding(.bottom, geometry.size.height * 0.05) // Bottom padding (1x)
                
                // Ente logo in top right corner
                VStack {
                    HStack {
                        Spacer()
                        EnteBranding()
                            .padding(.top, 30)
                            .padding(.trailing, 30)
                    }
                    
                    Spacer()
                }
            }
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            pulseScale = 1.05
        }
    }
}

struct InstructionStep: View {
    let number: String
    let text: String
    let icon: String
    let geometry: GeometryProxy
    
    var body: some View {
        VStack(spacing: geometry.size.height * 0.015) {
            // Circular icon background
            ZStack {
                Circle()
                    .fill(Color(red: 0/255, green: 150/255, blue: 51/255))
                    .frame(width: geometry.size.width * 0.035,
                           height: geometry.size.width * 0.035)
                
                Image(systemName: icon)
                    .font(.system(size: geometry.size.width * 0.015, weight: .medium))
                    .foregroundColor(.white)
            }
            
            // Step text
            Text(text)
                .font(FontUtils.interMedium(size: geometry.size.width * 0.012))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    PairingView(deviceCode: "W68GT1")
}
