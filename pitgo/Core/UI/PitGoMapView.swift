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
    /// Quando definido, uma nova coordenada só move a câmera quando este gatilho mudar. Permite
    /// atualizar o marcador em tempo real sem desfazer um pan manual.
    var centerTrigger: Int?
    var showsUserLocation: Bool = false
    /// `021`: quando presente (≥2 coordenadas), enquadra todas juntas (`setVisibleCoordinates`) em
    /// vez de centralizar num único ponto — usado pelo acompanhamento pós-confirmação do PitTec
    /// para mostrar cliente + prestador simultaneamente. Tem prioridade sobre `centerCoordinate`
    /// quando ambos são fornecidos.
    var fitCoordinates: [CLLocationCoordinate2D]?
    /// `026` FR-014: o enquadramento só é refeito quando este valor muda — nunca automaticamente a
    /// cada atualização de `fitCoordinates` (que muda a cada novo fix de localização). O chamador
    /// incrementa para reenquadrar explicitamente (abertura inicial, botão "Centralizar").
    var fitTrigger: Int = 0
    /// `026`: espaço reservado na borda inferior do mapa para o resumo compacto/expandido não
    /// cobrir os marcadores enquadrados — em pontos, já incluindo a margem de segurança.
    var fitBottomPadding: CGFloat = 60
    var onAnnotationSelected: ((String) -> Void)?
    /// Reportado ao final de um gesto do usuário (pan/zoom) — usado pelo botão "Buscar nesta área".
    var onRegionChanged: ((CLLocationCoordinate2D) -> Void)?
    /// Chamado somente quando o delegate identifica gesto de toque/arrasto do usuário.
    var onUserGesture: (() -> Void)?
    /// Linha simples entre dois ou mais pontos — usada como estimativa direta quando não há rota
    /// calculada (`015` FR-023: "identificando como estimativa", nunca como orientação viária real).
    /// `nil`/vazio remove a linha.
    var routeLine: [CLLocationCoordinate2D]?
    /// Versão autoritativa da rota viária; evita reescrever GeoJSON quando só o marcador muda.
    var routeVersion: Int64?
    /// As linhas de estimativa direta permanecem tracejadas; rotas do roteador são sólidas.
    var routeIsEstimated = true

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = LayoutAwareMapView(frame: .zero, styleURL: ManagedMapStyleConfiguration.current.styleURL)
        mapView.delegate = context.coordinator
        mapView.onLayout = { [weak coordinator = context.coordinator] map in
            coordinator?.applyPendingFit(in: map)
        }
        mapView.showsUserLocation = showsUserLocation
        if let fitCoordinates, fitCoordinates.count >= 2 {
            context.coordinator.requestFit(fitCoordinates, trigger: fitTrigger, padding: fitBottomPadding, in: mapView)
        } else if let centerCoordinate {
            mapView.setCenter(centerCoordinate, zoomLevel: zoomLevel, animated: false)
            context.coordinator.lastCenteredCoordinate = centerCoordinate
            context.coordinator.lastCenterTrigger = centerTrigger
        }
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        mapView.showsUserLocation = showsUserLocation
        context.coordinator.onAnnotationSelected = onAnnotationSelected
        context.coordinator.onRegionChanged = onRegionChanged
        context.coordinator.onUserGesture = onUserGesture

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
            // `026` FR-014/SC-006: só reenquadra quando `fitTrigger` muda de fato — nunca a cada
            // atualização de localização, para não sobrescrever um pan/zoom manual do cliente.
            if context.coordinator.lastFitTrigger != fitTrigger {
                context.coordinator.requestFit(fitCoordinates, trigger: fitTrigger, padding: fitBottomPadding, in: mapView)
            }
        } else if let centerCoordinate {
            let shouldCenter: Bool
            if let centerTrigger {
                shouldCenter = centerTrigger != context.coordinator.lastCenterTrigger
            } else {
                shouldCenter = centerCoordinate != context.coordinator.lastCenteredCoordinate
            }
            if shouldCenter {
                mapView.setCenter(centerCoordinate, zoomLevel: zoomLevel, animated: true)
                context.coordinator.lastCenteredCoordinate = centerCoordinate
                context.coordinator.lastCenterTrigger = centerTrigger
            }
        }

        if let routeVersion {
            if context.coordinator.currentRouteVersion != routeVersion {
                context.coordinator.currentRouteLine = routeLine
                context.coordinator.currentRouteVersion = routeVersion
                context.coordinator.currentRouteIsEstimated = routeIsEstimated
                Self.applyRouteLine(routeLine, estimated: routeIsEstimated, to: mapView.style)
            }
        } else {
            context.coordinator.currentRouteVersion = nil
            context.coordinator.currentRouteLine = routeLine
            context.coordinator.currentRouteIsEstimated = routeIsEstimated
            Self.applyRouteLine(routeLine, estimated: routeIsEstimated, to: mapView.style)
        }
    }

    /// `021`/`026`: enquadra todas as coordenadas dadas com um padding seguro — usado para mostrar
    /// cliente + PitTec juntos, sem sobrescrever um pan/zoom manual em toda atualização (só refeito
    /// quando `fitTrigger` muda de fato, ver `updateUIView`). `bottomPadding` reserva a área do
    /// resumo compacto/expandido para os marcadores não ficarem escondidos atrás dele.
    private static func fit(_ coordinates: [CLLocationCoordinate2D], in mapView: MLNMapView, bottomPadding: CGFloat, animated: Bool) {
        let padding = UIEdgeInsets(top: 60, left: 48, bottom: bottomPadding, right: 48)
        coordinates.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            mapView.setVisibleCoordinates(baseAddress, count: UInt(buffer.count), edgePadding: padding, animated: animated)
        }
    }

    fileprivate static func applyRouteLine(_ routeLine: [CLLocationCoordinate2D]?, estimated: Bool = true, to style: MLNStyle?) {
        guard let style else { return }
        guard let routeLine, routeLine.count >= 2 else {
            if let layer = style.layer(withIdentifier: Self.routeLineLayerID) { style.removeLayer(layer) }
            if let source = style.source(withIdentifier: Self.routeLineSourceID) { style.removeSource(source) }
            return
        }
        let polyline = MLNPolylineFeature(coordinates: routeLine, count: UInt(routeLine.count))
        if let source = style.source(withIdentifier: Self.routeLineSourceID) as? MLNShapeSource {
            source.shape = polyline
            if let layer = style.layer(withIdentifier: Self.routeLineLayerID) as? MLNLineStyleLayer {
                layer.lineDashPattern = estimated ? NSExpression(forConstantValue: [2, 2]) : nil
            }
        } else {
            let source = MLNShapeSource(identifier: Self.routeLineSourceID, shape: polyline)
            style.addSource(source)
            let layer = MLNLineStyleLayer(identifier: Self.routeLineLayerID, source: source)
            layer.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
            layer.lineWidth = NSExpression(forConstantValue: 3)
            layer.lineDashPattern = estimated ? NSExpression(forConstantValue: [2, 2]) : nil
            style.addLayer(layer)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onAnnotationSelected: onAnnotationSelected, onRegionChanged: onRegionChanged, onUserGesture: onUserGesture)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var onAnnotationSelected: ((String) -> Void)?
        var onRegionChanged: ((CLLocationCoordinate2D) -> Void)?
        var onUserGesture: (() -> Void)?
        var lastCenteredCoordinate: CLLocationCoordinate2D?
        var lastCenterTrigger: Int?
        private var regionChangeWasUserGesture = false
        /// `026`: último `fitTrigger` aplicado — só reenquadra quando ele muda (mesmo espírito de
        /// `lastCenteredCoordinate` para `centerCoordinate`, ver FR-014).
        var lastFitTrigger: Int?
        private var pendingFit: (coordinates: [CLLocationCoordinate2D], trigger: Int, padding: CGFloat)?

        func requestFit(_ coordinates: [CLLocationCoordinate2D], trigger: Int, padding: CGFloat, in map: MLNMapView) {
            pendingFit = (coordinates, trigger, padding)
            applyPendingFit(in: map)
        }

        func applyPendingFit(in map: MLNMapView) {
            // makeUIView ainda tem frame zero; só consome o gatilho após o layout real.
            guard map.bounds.width > 0, map.bounds.height > 0, let request = pendingFit else { return }
            pendingFit = nil
            PitGoMapView.fit(request.coordinates, in: map, bottomPadding: request.padding, animated: false)
            lastFitTrigger = request.trigger
        }
        /// Reaplicado em `didFinishLoading` — cobre o caso de `routeLine` ter sido pedido antes de o
        /// estilo (assíncrono) terminar de carregar.
        var currentRouteLine: [CLLocationCoordinate2D]?
        var currentRouteVersion: Int64?
        var currentRouteIsEstimated = true

        init(onAnnotationSelected: ((String) -> Void)?, onRegionChanged: ((CLLocationCoordinate2D) -> Void)?, onUserGesture: (() -> Void)?) {
            self.onAnnotationSelected = onAnnotationSelected
            self.onRegionChanged = onRegionChanged
            self.onUserGesture = onUserGesture
        }

        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            guard let identified = annotation as? IdentifiedPointAnnotation else { return }
            onAnnotationSelected?(identified.identifier)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            let wasUserGesture = regionChangeWasUserGesture
            regionChangeWasUserGesture = false
            // MapLibre also calls this delegate after programmatic camera changes. Treat only a
            // real pan/zoom as user movement; consumers such as the towing destination picker use
            // this callback to invalidate a typed address and reverse-geocode the map center.
            guard wasUserGesture else { return }
            let center = mapView.centerCoordinate
            // Remember the map's actual post-gesture center before notifying SwiftUI. Otherwise
            // updateUIView sees the new center as a fresh camera command and recenters at the
            // default zoom, making manual pan/zoom feel locked.
            lastCenteredCoordinate = center
            onRegionChanged?(center)
            onUserGesture?()
        }

        func mapView(_ mapView: MLNMapView, regionWillChangeAnimated animated: Bool) {
            regionChangeWasUserGesture = mapView.gestureRecognizers?.contains {
                $0.state == .began || $0.state == .changed
            } ?? false
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            currentRouteVersion = nil // estilo novo exige reinstalar o GeoJSON mesmo com a mesma versão
            PitGoMapView.applyRouteLine(currentRouteLine, estimated: currentRouteIsEstimated, to: style)
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

private final class LayoutAwareMapView: MLNMapView {
    var onLayout: ((MLNMapView) -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}
