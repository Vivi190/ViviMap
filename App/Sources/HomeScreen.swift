import AppCore
import CoreLocation
import DesignSystem
import Diagnostics
import LocationEngine
import MapEngine
import SearchEngine
import SwiftUI

enum Defaults {
    static var istanbul: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784) }
}

/// Viewport values MapLibre reports on every frame. Kept out of HomeScreen's state so that only the views
/// reading them (the compass) re-render while the map moves.
@MainActor
@Observable
final class MapViewport {
    var bearing: Double = 0
    var zoom: Double = 15
    var pitch: Double = 0
    var center = Defaults.istanbul

    func update(from proxy: MapViewProxy) {
        if abs(proxy.direction - bearing) > 0.5 { bearing = proxy.direction }
        zoom = proxy.zoomLevel
        pitch = proxy.pitch
        center = proxy.centerCoordinate
    }
}

struct HomeScreen: View {
    enum Sheet: String, Identifiable {
        case search, mapSettings, diagnostics, attribution
        var id: String { rawValue }
    }

    @Environment(AppSettings.self) private var settings
    @Environment(LocationProvider.self) private var location
    @Environment(\.openURL) private var openURL

    @State private var camera: MapViewCamera
    @State private var viewport = MapViewport()
    @State private var isNight: Bool
    @State private var is3D = false
    @State private var awaitingFirstFix: Bool
    @State private var sheet: Sheet?
    @State private var search = SearchController()
    @State private var selectedPlace: Place?

    private static let pitch3D: Double = 55

    init(startsTracking: Bool, initiallyNight: Bool) {
        _camera = State(initialValue: startsTracking ? .trackUserLocation(zoom: 15.5) : .center(Defaults.istanbul, zoom: 10))
        _awaitingFirstFix = State(initialValue: !startsTracking)
        _isNight = State(initialValue: initiallyNight)
    }

    var body: some View {
        ZStack {
            AtlasMapView(
                camera: $camera,
                appearance: isNight ? .night : .day,
                showsBuildings3D: is3D,
                destination: selectedPlace?.point.coordinate
            ) { proxy in
                viewport.update(from: proxy)
            }
            .ignoresSafeArea()

            overlay
        }
        .preferredColorScheme(isNight ? .dark : .light)
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
                .environment(settings)
                .environment(location)
                .preferredColorScheme(isNight ? .dark : .light)
        }
        .task(id: settings.appearanceMode) {
            // Re-evaluated every minute; reads here are not observed, so GPS fixes don't re-render the screen.
            while !Task.isCancelled {
                let anchor = location.lastLocation?.coordinate ?? Defaults.istanbul
                let night = settings.appearanceMode.isNight(at: .now, latitude: anchor.latitude, longitude: anchor.longitude)
                if night != isNight { isNight = night }
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onAppear {
            search.origin = { [location] in location.lastLocation.map { GeoPoint($0.coordinate) } }
        }
        .onChange(of: location.hasFix) { _, hasFix in
            // First fix after a cold start: jump to the user unless they already moved the map.
            guard hasFix, awaitingFirstFix else { return }
            awaitingFirstFix = false
            if camera.trackingMode == .none, !userMovedMap {
                camera = .trackUserLocation(zoom: 15.5)
            }
        }
    }

    // MARK: Overlay

    private var overlay: some View {
        VStack(spacing: Spacing.s) {
            HStack(alignment: .top, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    SearchBarButton { sheet = .search }
                    GPSStatusChip(openSettings: openSettings, showDiagnostics: { sheet = .diagnostics })
                }
                VStack(spacing: Spacing.m) {
                    controls
                    CompassButton(viewport: viewport, action: resetNorth)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                SpeedOverlay()
                Spacer(minLength: 0)
                if selectedPlace == nil {
                    Button { sheet = .attribution } label: {
                        Text("© OpenStreetMap")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Spacing.s)
                            .padding(.vertical, Spacing.xs)
                            .atlasFloatingSurface(in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Harita kaynakları"))
                }
            }
            if let place = selectedPlace {
                PlaceCard(place: place) { selectedPlace = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: selectedPlace)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }

    private var controls: some View {
        MapControlGroup {
            MapControlButton(systemImage: "map", label: "Harita ayarları") { sheet = .mapSettings }
            MapControlDivider()
            MapControlTextButton(title: is3D ? "2D" : "3D", label: "Üç boyutlu görünüm", isActive: is3D, action: toggle3D)
            MapControlDivider()
            MapControlButton(
                systemImage: locationSymbol,
                label: "Konumumu göster",
                isActive: camera.trackingMode != .none,
                action: locationTapped
            )
        }
        .sensoryFeedback(.selection, trigger: camera.trackingMode)
        .sensoryFeedback(.selection, trigger: is3D)
    }

    private var locationSymbol: String {
        switch camera.trackingMode {
        case .none: "location"
        case .follow: "location.fill"
        case .followDirection: "location.north.line.fill"
        }
    }

    private var userMovedMap: Bool {
        switch camera.lastReasonForChange {
        case .gesturePan, .gesturePinch, .gestureRotate, .gestureZoomIn, .gestureZoomOut, .gestureOneFingerZoom, .gestureTilt:
            true
        default:
            false
        }
    }

    // MARK: Actions

    private func locationTapped() {
        guard location.isAuthorized else {
            if location.isDenied { openSettings() } else { location.start() }
            return
        }
        let isDriving = (location.speedReading(at: .now).kmh ?? 0) >= 15
        camera = camera.nextTrackingCamera(zoom: max(viewport.zoom, 15), pitch: is3D ? Self.pitch3D : 0, isDriving: isDriving)
    }

    private func toggle3D() {
        is3D.toggle()
        let pitch = is3D ? Self.pitch3D : 0
        // Extruded buildings start at z15, so entering 3D zooms in far enough to see them.
        let zoom = is3D ? max(viewport.zoom, 16) : viewport.zoom
        if camera.trackingMode == .none {
            camera = .center(viewport.center, zoom: zoom, pitch: pitch, direction: viewport.bearing)
        } else {
            camera.setZoom(zoom)
            camera.setPitch(pitch)
        }
    }

    private func resetNorth() {
        if camera.trackingMode == .followDirection {
            camera = .trackUserLocation(zoom: viewport.zoom, pitch: viewport.pitch)
        } else if camera.trackingMode == .follow {
            camera.setDirection(0)
        } else {
            camera = .center(viewport.center, zoom: viewport.zoom, pitch: viewport.pitch, direction: 0)
        }
    }

    private func select(_ place: Place) {
        search.remember(place)
        selectedPlace = place
        sheet = nil
        camera = .center(place.point.coordinate, zoom: max(viewport.zoom, 16), pitch: is3D ? Self.pitch3D : 0)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    @ViewBuilder private func sheetContent(_ sheet: Sheet) -> some View {
        NavigationStack {
            switch sheet {
            case .search: SearchSheet(search: search, onSelect: select)
            case .mapSettings: MapSettingsView(showDiagnostics: { self.sheet = .diagnostics })
            case .diagnostics: LocationDiagnosticsView()
            case .attribution: MapAttributionView()
            }
        }
        .presentationDetents(sheet == .search ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Appears only while the map is rotated; tapping it turns north up again.
struct CompassButton: View {
    let viewport: MapViewport
    let action: () -> Void

    var body: some View {
        let bearing = viewport.bearing
        let offNorth = min(bearing.truncatingRemainder(dividingBy: 360), 360 - bearing.truncatingRemainder(dividingBy: 360))
        ZStack {
            if offNorth > 1 {
                Button(action: action) {
                    VStack(spacing: 0) {
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.atlasCritical)
                        Text("K")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .rotationEffect(.degrees(-bearing))
                    .frame(width: Metrics.tapTarget, height: Metrics.tapTarget)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .atlasFloatingSurface(in: Circle())
                .accessibilityLabel(Text("Kuzeyi yukarı al"))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: offNorth > 1)
    }
}
