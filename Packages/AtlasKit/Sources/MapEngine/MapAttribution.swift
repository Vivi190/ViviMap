import SwiftUI

/// Data and software credits required by the OSM, OpenMapTiles and OpenFreeMap licences.
public struct MapAttributionView: View {
    public init() {}

    public var body: some View {
        List {
            Section("Harita verisi") {
                link("© OpenStreetMap katkıcıları (ODbL)", "https://www.openstreetmap.org/copyright")
                link("© OpenMapTiles", "https://www.openmaptiles.org/")
                link("Karolar: OpenFreeMap", "https://openfreemap.org/")
            }
            Section("İşletmeler") {
                // Per record CDLA-Permissive-2.0, Apache-2.0 or CC0-1.0; the licences ask for this notice.
                link("Overture Maps Foundation: Meta, Microsoft, Foursquare ve diğer kaynaklar", "https://docs.overturemaps.org/attribution/")
            }
            Section("İstanbul Büyükşehir Belediyesi") {
                link("Otoparklarda boş yer: İSPARK, İBB Açık Veri Portalı", "https://data.ibb.gov.tr/license")
                link("Sinyalize kavşaklar: İBB Açık Veri Portalı", "https://data.ibb.gov.tr/license")
            }
            Section("Trafik") {
                link("Canlı trafik ve trafikli süreler: © HERE", "https://legal.here.com/")
            }
            Section("Yazılım") {
                link("MapLibre Native (BSD-2)", "https://github.com/maplibre/maplibre-native")
                link("MapLibre SwiftUI DSL (BSD-3)", "https://github.com/maplibre/swiftui-dsl")
            }
            Section {
                link("Haritada hata bildir", "https://www.openstreetmap.org/fixthemap")
            }
        }
        .navigationTitle("Harita kaynakları")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func link(_ title: String, _ url: String) -> some View {
        // Literal URLs above are valid; a nil here would be a typo caught in review.
        Link(title, destination: URL(string: url)!)
    }
}
