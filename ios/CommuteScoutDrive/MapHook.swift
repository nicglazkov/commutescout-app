import MapLibre
import SwiftUI
import UIKit

/// A hidden view placed next to the map that finds the MapLibre view in
/// the same window and adds what the navigation view does not expose:
/// taps on markers, long-press to drop a pin, the visible area for
/// loading markers, the heading for the compass button, the traffic
/// overlay, and the standard touch gestures (rotate, tilt, quick zoom).
struct MapHook: UIViewRepresentable {
    let layerIds: Set<String>
    var trafficTiles: String?
    var onTap: (CLLocationCoordinate2D, [String]) -> Void      // coordinate, marker keys hit
    var onLongPress: (CLLocationCoordinate2D) -> Void
    var onView: (MLNCoordinateBounds, Double, CLLocationDirection, CLLocationCoordinate2D) -> Void  // bounds, zoom, heading, center

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> HookView {
        let v = HookView()
        v.coordinator = context.coordinator
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: HookView, context: Context) {
        let c = context.coordinator
        c.layerIds = layerIds
        c.onTap = onTap
        c.onLongPress = onLongPress
        c.onView = onView
        c.trafficTiles = trafficTiles
        c.applyTraffic()
    }

    final class HookView: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.findMap() }
        }

        private func findMap() {
            var v: UIView? = self
            while let s = v?.superview {
                if let mv = Self.find(in: s) { coordinator?.attach(mv); return }
                v = s
            }
        }

        private static func find(in view: UIView) -> MLNMapView? {
            if let mv = view as? MLNMapView { return mv }
            for sub in view.subviews { if let mv = find(in: sub) { return mv } }
            return nil
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var mapView: MLNMapView?
        var layerIds: Set<String> = []
        var trafficTiles: String?
        var onTap: ((CLLocationCoordinate2D, [String]) -> Void)?
        var onLongPress: ((CLLocationCoordinate2D) -> Void)?
        var onView: ((MLNCoordinateBounds, Double, CLLocationDirection, CLLocationCoordinate2D) -> Void)?
        private var timer: Timer?
        private var last: (sw: CLLocationCoordinate2D, ne: CLLocationCoordinate2D, zoom: Double, heading: Double)?

        func attach(_ mv: MLNMapView) {
            guard mapView !== mv else { return }
            mapView = mv
            NSLog("CS hook attached to map view")
            // The gestures a maps app is expected to have.
            mv.allowsRotating = true
            mv.allowsTilting = true
            mv.allowsZooming = true
            mv.allowsScrolling = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.delegate = self
            for g in mv.gestureRecognizers ?? [] {
                if let t = g as? UITapGestureRecognizer, t.numberOfTapsRequired == 2 { tap.require(toFail: t) }
            }
            mv.addGestureRecognizer(tap)
            let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
            press.minimumPressDuration = 0.6
            press.delegate = self
            mv.addGestureRecognizer(press)
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.poll() }
            applyTraffic()
        }

        @objc private func tapped(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let mv = mapView else { return }
            let pt = g.location(in: mv)
            var feats = mv.visibleFeatures(at: pt, styleLayerIdentifiers: layerIds)
            if feats.isEmpty {
                feats = mv.visibleFeatures(in: CGRect(x: pt.x - 22, y: pt.y - 22, width: 44, height: 44),
                                           styleLayerIdentifiers: layerIds)
            }
            let keys = feats.compactMap { $0.attribute(forKey: "key") as? String }
            NSLog("CS tap at %@: %d features, layers %@", NSCoder.string(for: pt), feats.count,
                  (mv.style?.layers.map(\.identifier).filter { $0.hasPrefix("cs-") } ?? []).joined(separator: ","))
            onTap?(mv.convert(pt, toCoordinateFrom: mv), keys)
        }

        @objc private func pressed(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let mv = mapView else { return }
            onLongPress?(mv.convert(g.location(in: mv), toCoordinateFrom: mv))
        }

        private func poll() {
            guard let mv = mapView else { return }
            let b = mv.visibleCoordinateBounds
            let z = mv.zoomLevel, h = mv.direction
            if let last, abs(last.sw.latitude - b.sw.latitude) < 1e-5, abs(last.sw.longitude - b.sw.longitude) < 1e-5,
               abs(last.ne.latitude - b.ne.latitude) < 1e-5, abs(last.zoom - z) < 0.01, abs(last.heading - h) < 0.5 {
                return
            }
            last = (b.sw, b.ne, z, h)
            onView?(b, z, h, mv.centerCoordinate)
            applyTraffic()   // a style reload drops the overlay; put it back
        }

        /// The traffic raster from the site, on or off, surviving style reloads.
        func applyTraffic() {
            guard let style = mapView?.style else { return }
            let existing = style.layer(withIdentifier: "cs-traffic")
            if let tiles = trafficTiles {
                guard existing == nil else { return }
                let source = MLNRasterTileSource(identifier: "cs-traffic", tileURLTemplates: [tiles],
                                                 options: [.tileSize: 256, .maximumZoomLevel: 16])
                style.addSource(source)
                let layer = MLNRasterStyleLayer(identifier: "cs-traffic", source: source)
                layer.rasterOpacity = NSExpression(forConstantValue: 0.75)
                if let base = style.layer(withIdentifier: "base") { style.insertLayer(layer, above: base) }
                else { style.addLayer(layer) }
            } else if let existing {
                style.removeLayer(existing)
                if let src = style.source(withIdentifier: "cs-traffic") { style.removeSource(src) }
            }
        }

        func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool { true }
    }
}
