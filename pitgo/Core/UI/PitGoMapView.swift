//
//  PitGoMapView.swift
//  pitgo
//
//  Wrapper `UIViewRepresentable` único sobre `MLNMapView` (MapLibre Native iOS — ver research.md §7
//  de `009`, "mesmo provedor de mapa self-hosted do Android"). Reutilizado por `ServiceMapView`
//  (US4) e `AppointmentTrackingView` (US3). Sem clustering nesta camada — `ServiceMapView` adiciona
//  sua própria `MLNShapeSource` clusterizada quando precisar (ver research.md §7).
//

import CoreLocation
import MapLibre
import SwiftUI

struct PitGoMapAnnotationItem: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    /// SF Symbol para um marcador distinto do pino padrão — usado pelo ícone de carro do prestador
    /// móvel (`013`, FR-011). `nil` preserva o pino nativo (endereço fixo, `010`).
    let symbolName: String?

    init(id: String, coordinate: CLLocationCoordinate2D, title: String? = nil, subtitle: String? = nil, symbolName: String? = nil) {
        self.id = id
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
    }
}

struct PitGoMapView: UIViewRepresentable {
    private static let routeLineSourceID = "pitgo.routeLine.source"
    private static let routeLineLayerID = "pitgo.routeLine.layer"

    let annotations: [PitGoMapAnnotationItem]
    var centerCoordinate: CLLocationCoordinate2D?
    var zoomLevel: Double = 13
    var showsUserLocation: Bool = false
    /// `021`: quando presente (≥2 coordenadas), enquadra todas juntas (`setVisibleCoordinates`) em
    /// vez de centralizar num único ponto — usado pelo acompanhamento pós-confirmação do PitTec
    /// para mostrar cliente + prestador simultaneamente. Tem prioridade sobre `centerCoordinate`
    /// quando ambos são fornecidos.
    var fitCoordinates: [CLLocationCoordinate2D]?
    var onAnnotationSelected: ((String) -> Void)?
    /// Reportado ao final de um gesto do usuário (pan/zoom) — usado pelo botão "Buscar nesta área".
    var onRegionChanged: ((CLLocationCoordinate2D) -> Void)?
    /// Linha simples entre dois ou mais pontos — usada como estimativa direta quando não há rota
    /// calculada (`015` FR-023: "identificando como estimativa", nunca como orientação viária real).
    /// `nil`/vazio remove a linha.
    var routeLine: [CLLocationCoordinate2D]?

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: ManagedMapStyleConfiguration.current.styleURL)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation
        if let fitCoordinates, fitCoordinates.count >= 2 {
            Self.fit(fitCoordinates, in: mapView, animated: false)
            context.coordinator.lastFittedCoordinates = fitCoordinates
        } else if let centerCoordinate {
            mapView.setCenter(centerCoordinate, zoomLevel: zoomLevel, animated: false)
            context.coordinator.lastCenteredCoordinate = centerCoordinate
        }
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        mapView.showsUserLocation = showsUserLocation
        context.coordinator.onAnnotationSelected = onAnnotationSelected
        context.coordinator.onRegionChanged = onRegionChanged

        let existing = mapView.annotations ?? []
        mapView.removeAnnotations(existing)
        let pointAnnotations = annotations.map { item -> IdentifiedPointAnnotation in
            let point = IdentifiedPointAnnotation(identifier: item.id, symbolName: item.symbolName)
            point.coordinate = item.coordinate
            point.title = item.title
            point.subtitle = item.subtitle
            return point
        }
        mapView.addAnnotations(pointAnnotations)

        if let fitCoordinates, fitCoordinates.count >= 2 {
            if fitCoordinates != context.coordinator.lastFittedCoordinates {
                Self.fit(fitCoordinates, in: mapView, animated: true)
                context.coordinator.lastFittedCoordinates = fitCoordinates
            }
        } else if let centerCoordinate, centerCoordinate != context.coordinator.lastCenteredCoordinate {
            mapView.setCenter(centerCoordinate, zoomLevel: zoomLevel, animated: true)
            context.coordinator.lastCenteredCoordinate = centerCoordinate
        }

        context.coordinator.currentRouteLine = routeLine
        Self.applyRouteLine(routeLine, to: mapView.style)
    }

    /// `021`: enquadra todas as coordenadas dadas com um padding seguro — usado para mostrar
    /// cliente + PitTec juntos, sem sobrescrever um pan/zoom manual em toda atualização (só refeito
    /// quando `fitCoordinates` muda de fato, ver `updateUIView`).
    private static func fit(_ coordinates: [CLLocationCoordinate2D], in mapView: MLNMapView, animated: Bool) {
        let padding = UIEdgeInsets(top: 60, left: 48, bottom: 60, right: 48)
        coordinates.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            mapView.setVisibleCoordinates(baseAddress, count: UInt(buffer.count), edgePadding: padding, animated: animated)
        }
    }

    fileprivate static func applyRouteLine(_ routeLine: [CLLocationCoordinate2D]?, to style: MLNStyle?) {
        guard let style else { return }
        guard let routeLine, routeLine.count >= 2 else {
            if let layer = style.layer(withIdentifier: Self.routeLineLayerID) { style.removeLayer(layer) }
            if let source = style.source(withIdentifier: Self.routeLineSourceID) { style.removeSource(source) }
            return
        }
        let polyline = MLNPolylineFeature(coordinates: routeLine, count: UInt(routeLine.count))
        if let source = style.source(withIdentifier: Self.routeLineSourceID) as? MLNShapeSource {
            source.shape = polyline
        } else {
            let source = MLNShapeSource(identifier: Self.routeLineSourceID, shape: polyline)
            style.addSource(source)
            let layer = MLNLineStyleLayer(identifier: Self.routeLineLayerID, source: source)
            layer.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
            layer.lineWidth = NSExpression(forConstantValue: 3)
            layer.lineDashPattern = NSExpression(forConstantValue: [2, 2]) // tracejada = estimativa, nunca rota real
            style.addLayer(layer)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onAnnotationSelected: onAnnotationSelected, onRegionChanged: onRegionChanged)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var onAnnotationSelected: ((String) -> Void)?
        var onRegionChanged: ((CLLocationCoordinate2D) -> Void)?
        var lastCenteredCoordinate: CLLocationCoordinate2D?
        /// `021`: última lista enquadrada via `fitCoordinates`, para só reenquadrar quando ela muda
        /// de fato (mesmo espírito de `lastCenteredCoordinate` para `centerCoordinate`).
        var lastFittedCoordinates: [CLLocationCoordinate2D]?
        /// Reaplicado em `didFinishLoading` — cobre o caso de `routeLine` ter sido pedido antes de o
        /// estilo (assíncrono) terminar de carregar.
        var currentRouteLine: [CLLocationCoordinate2D]?

        init(onAnnotationSelected: ((String) -> Void)?, onRegionChanged: ((CLLocationCoordinate2D) -> Void)?) {
            self.onAnnotationSelected = onAnnotationSelected
            self.onRegionChanged = onRegionChanged
        }

        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            guard let identified = annotation as? IdentifiedPointAnnotation else { return }
            onAnnotationSelected?(identified.identifier)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            onRegionChanged?(mapView.centerCoordinate)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            PitGoMapView.applyRouteLine(currentRouteLine, to: style)
        }

        /// Pino padrão do sistema quando `symbolName == nil` (endereço fixo, `010`); um círculo com
        /// SF Symbol para marcadores distintos (carro do prestador móvel, `013` FR-011) — forma e
        /// cor diferem do pino padrão, com `accessibilityLabel` equivalente ao `title`.
        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let identified = annotation as? IdentifiedPointAnnotation, let symbolName = identified.symbolName else {
                return nil
            }
            let reuseIdentifier = "pitgo.symbol.\(symbolName)"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) ?? MLNAnnotationView(reuseIdentifier: reuseIdentifier)
            view.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
            view.subviews.forEach { $0.removeFromSuperview() }

            let background = UIView(frame: view.bounds)
            background.backgroundColor = .systemBlue
            background.layer.cornerRadius = view.bounds.width / 2
            background.layer.borderColor = UIColor.white.cgColor
            background.layer.borderWidth = 2
            view.addSubview(background)

            let imageView = UIImageView(image: UIImage(systemName: symbolName)?.withTintColor(.white, renderingMode: .alwaysOriginal))
            imageView.contentMode = .scaleAspectFit
            imageView.frame = background.bounds.insetBy(dx: 7, dy: 7)
            background.addSubview(imageView)

            view.isAccessibilityElement = true
            view.accessibilityLabel = identified.title
            return view
        }
    }
}

/// `MLNPointAnnotation` não carrega um identificador de domínio — associamos um aqui para saber
/// qual `PitGoMapAnnotationItem` foi selecionado.
private nonisolated final class IdentifiedPointAnnotation: MLNPointAnnotation {
    let identifier: String
    let symbolName: String?

    init(identifier: String, symbolName: String? = nil) {
        self.identifier = identifier
        self.symbolName = symbolName
        super.init()
    }

    required init?(coder: NSCoder) {
        identifier = ""
        symbolName = nil
        super.init(coder: coder)
    }
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
