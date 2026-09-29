import SwiftUI

/// What `RideWithMeCard` opens: the same journey, driven.
///
/// Follows `RouteDetailView`'s shape — a scrolling column with the endpoints
/// laid out vertically — but the middle is a single drive instead of a sequence
/// of legs, and it carries no duration, because none is claimed anywhere.
struct RideWithMeDetailView: View {
    let origin: Station
    let destination: Station

    @Environment(\.openURL) private var openURL
    @State private var locationProvider = LocationProvider()
    @State private var isFetchingLocation = false
    @State private var locationFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                journey
                actions
                closing
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .navigationTitle(Chauffeur.badge)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Chauffeur.plate)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Brand.red, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(Chauffeur.detailTitle)
                .font(.system(size: 28, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    // MARK: - The journey, as one drive

    private var journey: some View {
        VStack(alignment: .leading, spacing: 0) {
            endpoint(origin.name, systemImage: "circle")

            // The connector: one continuous line, one car, no transfers.
            HStack(spacing: 14) {
                Rectangle()
                    .fill(Brand.red.opacity(0.45))
                    .frame(width: 3, height: 52)
                    .frame(width: 22)

                Label(Chauffeur.cardSubtitle, systemImage: "car.fill")
                    .font(.subheadline)
                    .foregroundStyle(Brand.red)
            }

            endpoint(destination.name, systemImage: "mappin.and.ellipse")
        }
        .padding(.bottom, 28)
    }

    private func endpoint(_ name: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.red)
                .frame(width: 22)

            Text(name)
                .font(.headline)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 10) {
            actionButton("Beni ara", systemImage: "phone.fill", prominent: true) {
                guard let phone = Chauffeur.phoneNumber else { return }
                open(Chauffeur.callURL(phone: phone))
            }

            actionButton("Mesaj at", systemImage: "message.fill") {
                open(smsURL(body: Chauffeur.messageBody(
                    from: origin.name, to: destination.name)))
            }

            // Addressed to her, like every other line in the app: "your
            // location", not "my location".
            actionButton(
                isFetchingLocation ? "Konum alınıyor…" : "Konumunu paylaş",
                systemImage: "location.fill"
            ) {
                shareLocation()
            }
            .disabled(isFetchingLocation)

            if locationFailed {
                hint("Konuma ulaşılamadı — Ayarlar'dan konum iznini açabilirsin.")
            }
        }
        // Everything here needs a number to reach. Absent `contact.json` the
        // buttons stay visible but inert, so the screen degrades instead of
        // silently doing nothing when tapped.
        .disabled(Chauffeur.phoneNumber == nil)
        .overlay(alignment: .bottom) {
            if Chauffeur.phoneNumber == nil {
                hint("Numara ayarlanmamış — `contact.json` eksik.")
                    .offset(y: 24)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(prominent ? .white : Brand.red)
                .background(
                    prominent ? AnyShapeStyle(Brand.red) : AnyShapeStyle(Brand.red.opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private var closing: some View {
        Text(Chauffeur.closingLine)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 28)
    }

    // MARK: - Plumbing

    /// Asks for one fix, then opens Messages with a map pin appended. A refused
    /// or failed lookup still sends the message — just without the pin — so the
    /// button is never a dead end.
    private func shareLocation() {
        isFetchingLocation = true
        locationFailed = false

        Task {
            let coordinate = await locationProvider.currentCoordinate()
            isFetchingLocation = false

            let body: String
            if let coordinate {
                body = Chauffeur.locationMessageBody(
                    from: origin.name,
                    to: destination.name,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            } else {
                locationFailed = true
                body = Chauffeur.messageBody(from: origin.name, to: destination.name)
            }

            open(smsURL(body: body))
        }
    }

    /// See `Chauffeur.messageURL` for why this is not `URLComponents`.
    private func smsURL(body: String) -> URL? {
        guard let phone = Chauffeur.phoneNumber else { return nil }
        return Chauffeur.messageURL(phone: phone, body: body)
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        openURL(url)
    }
}

#Preview {
    NavigationStack {
        RideWithMeDetailView(
            origin: Station(id: "kadikoy", name: "Kadıköy"),
            destination: Station(id: "levent", name: "Levent")
        )
    }
}
