import SwiftUI

/// Shown over the app at launch, so the first thing on screen is the brand
/// rather than an empty white page.
///
/// The system launch screen is a plain white field (see the
/// `UILaunchScreen_BackgroundColor` build setting); this view paints the same
/// white, so the handover is invisible and only the mark and wordmark appear
/// to fade in.
struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(Brand.red)
                    .scaleEffect(appeared ? 1 : 0.86)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 6) {
                    Text(Brand.tagline)
                        .font(.system(size: 21, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(Brand.red)

                    Text(Brand.name)
                        .font(.system(size: 33, weight: .bold, design: .serif))
                        .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.12))
                }
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
            }
            .padding(.horizontal, 24)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(Brand.tagline). \(Brand.name)")
            .accessibilityIdentifier("splash")
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { appeared = true }
        }
    }
}

#Preview {
    SplashView()
}
