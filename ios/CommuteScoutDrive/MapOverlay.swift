import MapLibre
import UIKit

/// Everything CommuteScout draws on the map, drawn by hand.
///
/// The SwiftUI map library removes and re-adds every layer it is given
/// on every view update, so markers drawn through it vanish and
/// reappear each time anything on screen changes: a location fix, a
/// toast, a sheet. This class owns its sources and layers in the live
/// style instead. A new set of markers replaces the data of one source,
/// which MapLibre swaps in without a frame of nothing; a scene that has
/// not changed costs nothing at all.
///
/// Icons scale with zoom, like the website: full size on a street,
/// small over a region, and a colored speck over the country, where a
/// circle layer stands in for the symbols. Nothing is held back by
/// zoom, so a dot is on the map at any zoom the map can reach.
@MainActor
final class MapOverlay {
    /// What the map should show. Each part carries a version string:
    /// when the string is unchanged the part is not touched.
    struct Scene {
        var markers: [MLNPointFeature] = []
        var markersVersion = ""
        var closures: [MLNShape] = []
        var tolls: [MLNShape] = []
        var fires: [MLNShape] = []
        var shapesVersion = ""
        var preview: MLNPolylineFeature?
        var previewVersion = ""
        var pin: CLLocationCoordinate2D?
        var pinVersion = ""
    }

    /// Layers a tap looks in, dots before lines.
    static let tappable: Set<String> = ["cs-markers", "cs-markers-plugin", "cs-closure-line", "cs-toll-line"]

    private weak var mapView: MLNMapView?
    private var applied = Scene()
    private var installedIn: MLNStyle?
    private var images: [String: UIImage] = [:]
    private var registered: Set<String> = []

    func attach(_ mv: MLNMapView) { mapView = mv }

    /// Bring the map to `scene`. Safe to call on every SwiftUI update.
    func apply(_ scene: Scene) {
        guard let style = mapView?.style else { return }
        if installedIn !== style { install(in: style) }
        if scene.markersVersion != applied.markersVersion {
            registerImages(for: scene.markers, in: style)
            source("cs-markers", in: style)?.shape = MLNShapeCollectionFeature(shapes: scene.markers)
        }
        if scene.shapesVersion != applied.shapesVersion {
            source("cs-closure-line", in: style)?.shape = MLNShapeCollectionFeature(shapes: scene.closures)
            source("cs-toll-line", in: style)?.shape = MLNShapeCollectionFeature(shapes: scene.tolls)
            source("cs-fire-area", in: style)?.shape = MLNShapeCollectionFeature(shapes: scene.fires)
        }
        if scene.previewVersion != applied.previewVersion {
            source("cs-route", in: style)?.shape = scene.preview.map { MLNShapeCollectionFeature(shapes: [$0]) }
                ?? MLNShapeCollectionFeature(shapes: [])
        }
        if scene.pinVersion != applied.pinVersion {
            source("cs-pin", in: style)?.shape = scene.pin.map { MLNShapeCollectionFeature(shapes: [MLNPointFeature(coordinate: $0)]) }
                ?? MLNShapeCollectionFeature(shapes: [])
        }
        applied = scene
    }

    /// A style reload (a new base map) drops every layer. The poll in
    /// the map hook calls this; when the style is a new one, everything
    /// is put back from the scene last applied.
    func restoreIfNeeded() {
        guard let style = mapView?.style, installedIn !== style else { return }
        let scene = applied
        applied = Scene()
        apply(scene)
    }

    private func source(_ id: String, in style: MLNStyle) -> MLNShapeSource? {
        style.source(withIdentifier: id) as? MLNShapeSource
    }

    // MARK: layers

    private func install(in style: MLNStyle) {
        installedIn = style
        registered = []
        let empty = MLNShapeCollectionFeature(shapes: [])
        func add(_ id: String, maxZoom: Float? = nil) -> MLNShapeSource {
            if let s = style.source(withIdentifier: id) as? MLNShapeSource { return s }
            var options: [MLNShapeSourceOption: Any] = [.buffer: 32]
            if let maxZoom { options[.maximumZoomLevel] = maxZoom }
            let s = MLNShapeSource(identifier: id, shape: empty, options: options)
            style.addSource(s)
            return s
        }
        func place(_ layer: MLNStyleLayer) {
            if let old = style.layer(withIdentifier: layer.identifier) { style.removeLayer(old) }
            style.addLayer(layer)
        }
        let on = NSExpression(forConstantValue: true)

        // Burn footprints, under everything else.
        let fires = add("cs-fire-area")
        let fireColor = UIColor(red: 0.85, green: 0.47, blue: 0.02, alpha: 1)
        let fireFill = MLNFillStyleLayer(identifier: "cs-fire-area", source: fires)
        fireFill.fillColor = NSExpression(forConstantValue: fireColor)
        fireFill.fillOpacity = NSExpression(forConstantValue: 0.25)
        place(fireFill)
        let fireEdge = MLNLineStyleLayer(identifier: "cs-fire-edge", source: fires)
        fireEdge.lineColor = NSExpression(forConstantValue: fireColor)
        fireEdge.lineWidth = NSExpression(forConstantValue: 1.5)
        place(fireEdge)

        // Closure stretches and toll corridors, along the carriageway.
        let closures = add("cs-closure-line")
        let closure = MLNLineStyleLayer(identifier: "cs-closure-line", source: closures)
        closure.lineColor = NSExpression(forConstantValue: UIColor(red: 0.84, green: 0.19, blue: 0.19, alpha: 1))
        closure.lineWidth = NSExpression(forConstantValue: 5)
        closure.lineOpacity = NSExpression(forConstantValue: 0.85)
        closure.lineCap = NSExpression(forConstantValue: "round")
        closure.lineJoin = NSExpression(forConstantValue: "round")
        place(closure)
        let tolls = add("cs-toll-line")
        let toll = MLNLineStyleLayer(identifier: "cs-toll-line", source: tolls)
        toll.lineColor = NSExpression(forConstantValue: UIColor(red: 0.49, green: 0.23, blue: 0.93, alpha: 1))
        toll.lineWidth = NSExpression(forConstantValue: 4)
        toll.lineDashPattern = NSExpression(forConstantValue: [2, 1.5])
        toll.lineJoin = NSExpression(forConstantValue: "round")
        place(toll)

        // The dots. Up to a region they are specks: a circle in the
        // kind's color (or the plugin's), drawn by the GPU however many
        // there are. From there on, the icons, scaled up with zoom.
        let markers = add("cs-markers", maxZoom: 14)
        let specks = MLNCircleStyleLayer(identifier: "cs-specks", source: markers)
        specks.circleColor = NSExpression(forKeyPath: "tint")
        specks.circleRadius = NSExpression(forMLNInterpolating: .zoomLevelVariable, curveType: .linear, parameters: nil,
                                           stops: NSExpression(forConstantValue: [3: 2.2, 6: 3.5, Self.iconFromZoom: 5.5]))
        specks.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
        specks.circleStrokeWidth = NSExpression(forMLNInterpolating: .zoomLevelVariable, curveType: .linear, parameters: nil,
                                                stops: NSExpression(forConstantValue: [3: 0.6, Self.iconFromZoom: 1.2]))
        specks.circleOpacity = NSExpression(forConstantValue: 0.95)
        specks.maximumZoomLevel = Self.iconFromZoom
        place(specks)
        for (id, plugin) in [("cs-markers", false), ("cs-markers-plugin", true)] {
            let icons = MLNSymbolStyleLayer(identifier: id, source: markers)
            icons.iconImageName = NSExpression(forKeyPath: "icon")
            icons.iconScale = NSExpression(forMLNInterpolating: .zoomLevelVariable, curveType: .linear, parameters: nil,
                                           stops: NSExpression(forConstantValue: [Self.iconFromZoom: 0.42, 9.5: 0.55, 11.5: 0.8, 13: 1.0]))
            icons.iconAllowsOverlap = on
            icons.iconIgnoresPlacement = on
            icons.minimumZoomLevel = Self.iconFromZoom
            icons.predicate = NSPredicate(format: plugin ? "kind == 'plugin'" : "kind != 'plugin'")
            place(icons)
        }

        // The route under consideration, drawn like the navigation route.
        let route = add("cs-route")
        let border = MLNLineStyleLayer(identifier: "cs-route-border", source: route)
        border.lineColor = NSExpression(forConstantValue: UIColor(red: 0.11, green: 0.31, blue: 0.66, alpha: 1))
        border.lineWidth = NSExpression(forConstantValue: 9)
        border.lineCap = NSExpression(forConstantValue: "round")
        border.lineJoin = NSExpression(forConstantValue: "round")
        place(border)
        let line = MLNLineStyleLayer(identifier: "cs-route", source: route)
        line.lineColor = NSExpression(forConstantValue: UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1))
        line.lineWidth = NSExpression(forConstantValue: 6)
        line.lineCap = NSExpression(forConstantValue: "round")
        line.lineJoin = NSExpression(forConstantValue: "round")
        place(line)

        // The pin.
        let pin = add("cs-pin")
        let ring = MLNCircleStyleLayer(identifier: "cs-pin-ring", source: pin)
        ring.circleRadius = NSExpression(forConstantValue: 14)
        ring.circleColor = NSExpression(forConstantValue: UIColor(red: 0.18, green: 0.5, blue: 0.97, alpha: 0.25))
        place(ring)
        let dot = MLNCircleStyleLayer(identifier: "cs-pin", source: pin)
        dot.circleRadius = NSExpression(forConstantValue: 7)
        dot.circleColor = NSExpression(forConstantValue: UIColor(red: 0.18, green: 0.5, blue: 0.97, alpha: 1))
        dot.circleStrokeWidth = NSExpression(forConstantValue: 2)
        dot.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
        place(dot)
    }

    /// Where specks become icons. The speck's radius and the icon's
    /// scale meet here, so crossing it changes the shape, not the size.
    static let iconFromZoom: Float = 7.5

    // MARK: images

    /// A symbol layer names its image by a feature attribute; every
    /// name used must be registered with the style first.
    private func registerImages(for markers: [MLNPointFeature], in style: MLNStyle) {
        for f in markers {
            guard let name = f.attribute(forKey: "icon") as? String, !registered.contains(name) else { continue }
            guard let img = images[name] ?? Self.image(named: name) else { continue }
            images[name] = img
            style.setImage(img, forName: name)
            registered.insert(name)
        }
    }

    /// The image behind a name: `icon:<kind>` is an official kind's disc,
    /// `badge:<plugin>|<category>` a plugin badge.
    private static func image(named name: String) -> UIImage? {
        if name.hasPrefix("icon:") { return MarkerIcons.images[String(name.dropFirst(5))] }
        if name.hasPrefix("badge:") {
            let parts = name.dropFirst(6).split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return PluginStyle.image(sourceId: parts[0], category: parts[1])
        }
        return nil
    }

    /// One marker as a feature with everything the layers read.
    static func feature(for m: RoadMarker) -> MLNPointFeature {
        let f = MLNPointFeature(coordinate: m.coordinate)
        let icon: String
        let tint: UIColor
        if m.kind == "plugin" {
            let sid = PluginStyle.sourceId(m)
            icon = "badge:\(sid)|\(PluginStyle.category(m.flareKind))"
            tint = PluginStyle.color(sid)
        } else {
            icon = "icon:\(m.kind)"
            tint = MarkerIcons.color[m.kind] ?? .gray
        }
        f.attributes = ["key": m.key, "kind": m.kind, "geo": "dot", "icon": icon, "tint": tint.hex]
        return f
    }
}

extension UIColor {
    /// `#rrggbb`, the form a style expression reads as a color.
    var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
