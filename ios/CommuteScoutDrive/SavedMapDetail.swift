import Foundation
import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import SwiftUI

/// The first 127 bytes of a PMTiles file, read from the file itself:
/// what the file says it holds, as opposed to what the app wrote down
/// when it saved it.
struct PMTilesHeader {
    let version: Int
    let minZoom: Int
    let maxZoom: Int
    let south: Double, west: Double, north: Double, east: Double
    let tileCount: Int

    static func read(_ url: URL) -> PMTilesHeader? {
        guard let h = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: 127), data.count == 127,
              String(data: data[0 ..< 7], encoding: .ascii) == "PMTiles" else { return nil }
        func u64(_ at: Int) -> Int { data[at ..< at + 8].withUnsafeBytes { Int(truncatingIfNeeded: $0.loadUnaligned(as: UInt64.self)) } }
        func i32(_ at: Int) -> Double { Double(data[at ..< at + 4].withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }) / 1e7 }
        return PMTilesHeader(version: Int(data[7]), minZoom: Int(data[100]), maxZoom: Int(data[101]),
                             south: i32(106), west: i32(102), north: i32(114), east: i32(110),
                             tileCount: u64(72))
    }
}

/// One saved map, checked against the disk: the record the app kept,
/// what the file system says, and what the file's own header says. A
/// map that is "saved" is only saved when all three agree.
struct SavedMapDetail: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let file: MapFiles.LocalFile
    @State private var check: MapFiles.Check?
    @State private var confirmDelete = false

    private var bounds: MLNCoordinateBounds {
        MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: file.south, longitude: file.west),
                            ne: CLLocationCoordinate2D(latitude: file.north, longitude: file.east))
    }

    var body: some View {
        Form {
            Section {
                MapView(styleURL: model.styleURL, camera: .constant(.boundingBox(bounds, edgePadding: .init(top: 24, left: 24, bottom: 24, right: 24)))) {
                    let area = ShapeSource(identifier: "cs-saved-area") {
                        MLNPolygonFeature(coordinates: [
                            CLLocationCoordinate2D(latitude: file.south, longitude: file.west),
                            CLLocationCoordinate2D(latitude: file.south, longitude: file.east),
                            CLLocationCoordinate2D(latitude: file.north, longitude: file.east),
                            CLLocationCoordinate2D(latitude: file.north, longitude: file.west),
                            CLLocationCoordinate2D(latitude: file.south, longitude: file.west),
                        ], count: 5)
                    }
                    FillStyleLayer(identifier: "cs-saved-fill", source: area)
                        .fillColor(UIColor(red: 0.18, green: 0.5, blue: 0.97, alpha: 1)).fillOpacity(0.18)
                    LineStyleLayer(identifier: "cs-saved-edge", source: area)
                        .lineColor(UIColor(red: 0.18, green: 0.5, blue: 0.97, alpha: 1)).lineWidth(2)
                }
                .unsafeMapViewControllerModifier { c in
                    c.mapView.isUserInteractionEnabled = false
                    c.mapView.logoView.isHidden = true
                    c.mapView.attributionButton.isHidden = true
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .listRowInsets(EdgeInsets())
            } footer: {
                Text(file.kind == .state ? "The whole state, at every zoom." : "The road and a few miles either side of it.")
            }

            Section("Status") {
                if let c = check {
                    LabeledContent("File on disk") {
                        status(c.exists ? "Present" : "Missing", c.exists ? "checkmark.circle.fill" : "xmark.circle.fill", c.exists ? .green : .red)
                    }
                    if c.exists {
                        LabeledContent("Readable") {
                            status(c.header != nil ? "Yes, a PMTiles \(c.header?.version ?? 0) file" : "No, the file is damaged",
                                   c.header != nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                   c.header != nil ? .green : .orange)
                        }
                        LabeledContent("Size on disk", value: ByteCountFormatter.string(fromByteCount: c.bytesOnDisk, countStyle: .file))
                        if c.bytesOnDisk != file.bytes {
                            Text("The app recorded \(file.sizeText) when it saved this file.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack { ProgressView(); Text("Checking the file").foregroundStyle(.secondary) }
                }
                if model.mapFiles.usingLocal?.id == file.id {
                    Label("The map is drawing from this file right now", systemImage: "wifi.slash")
                }
            }

            if let h = check?.header {
                Section {
                    LabeledContent("Zoom levels", value: "\(h.minZoom) to \(h.maxZoom)")
                    LabeledContent("Tiles", value: h.tileCount.formatted())
                    LabeledContent("Covers", value: Self.area(h.south, h.west, h.north, h.east))
                } header: {
                    Text("What the file says")
                } footer: {
                    Text("Read from the file's own header, not from the app's notes about it.")
                }
            }

            Section("Record") {
                LabeledContent("Name", value: file.name)
                LabeledContent("Kind", value: file.kind == .state ? "Whole state" : "Trip corridor")
                LabeledContent("Saved", value: file.savedAt.formatted(date: .abbreviated, time: .shortened))
                if let b = file.build { LabeledContent("Map build", value: b) }
                LabeledContent("Covers", value: Self.area(file.south, file.west, file.north, file.east))
                LabeledContent("File", value: model.mapFiles.path(for: file).lastPathComponent)
                    .font(.footnote)
            }

            Section {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete this map", systemImage: "trash") }
            }
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { check = await model.mapFiles.check(file) }
        .confirmationDialog("Delete \(file.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { model.mapFiles.delete(file); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Without it the map needs a signal here.")
        }
    }

    /// A verdict with its mark, on one line.
    private func status(_ text: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text)
        }
        .foregroundStyle(color)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// `37.2°N to 38.1°N, 122.6°W to 121.7°W`.
    static func area(_ s: Double, _ w: Double, _ n: Double, _ e: Double) -> String {
        func lat(_ v: Double) -> String { String(format: "%.1f\u{00B0}%@", abs(v), v >= 0 ? "N" : "S") }
        func lon(_ v: Double) -> String { String(format: "%.1f\u{00B0}%@", abs(v), v >= 0 ? "E" : "W") }
        return "\(lat(s)) to \(lat(n)), \(lon(w)) to \(lon(e))"
    }
}
