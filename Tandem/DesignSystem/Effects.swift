import SwiftUI
import UIKit

/// The check-off moment: a paw print stamps onto the checkbox and a ring ripples out.
/// Plays whenever `trigger` changes, including when another caregiver's check-off arrives live.
struct PawStamp: View {
    let trigger: Int
    @State private var rippleScale: CGFloat = 0.6
    @State private var rippleOpacity = 0.0
    @State private var pawScale: CGFloat = 2.4
    @State private var pawOpacity = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.success, lineWidth: 2)
                .scaleEffect(rippleScale)
                .opacity(rippleOpacity)
            Image(systemName: "pawprint.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.onPrimary)
                .frame(width: 30, height: 30)
                .background(Theme.success, in: Circle())
                .rotationEffect(.degrees(-16))
                .scaleEffect(pawScale)
                .opacity(pawOpacity)
        }
        .frame(width: 34, height: 34)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { play() }
    }

    private func play() {
        rippleScale = 0.6
        rippleOpacity = 0.9
        pawScale = 2.4
        pawOpacity = 0
        withAnimation(.easeOut(duration: 0.6)) {
            rippleScale = 2.1
            rippleOpacity = 0
        }
        withAnimation(.spring(response: 0.26, dampingFraction: 0.5)) {
            pawScale = 1
            pawOpacity = 1
        }
        withAnimation(.easeIn(duration: 0.3).delay(0.55)) {
            pawOpacity = 0
        }
    }
}

/// The end-of-day moment: paw prints scatter out from the progress ring when the last task is done.
struct PawBurst: View {
    let trigger: Int
    @State private var progress: CGFloat = 1

    private let count = 7

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let angle = (Double(index) / Double(count)) * 2 * .pi - .pi / 2
                let distance = 30 + 34 * progress
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(index.isMultiple(of: 2) ? Theme.success : Theme.sun)
                    .rotationEffect(.radians(angle + .pi / 2))
                    .scaleEffect(0.5 + 0.7 * progress)
                    .offset(x: cos(angle) * distance, y: sin(angle) * distance)
                    .opacity(progress >= 1 ? 0 : Double(1 - progress * progress))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            progress = 0
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            withAnimation(.easeOut(duration: 0.9)) { progress = 1 }
        }
    }
}
