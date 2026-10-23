import SwiftUI

extension AddType {
    var title: LocalizedStringResource {
        switch self {
        case .photo: "Photo"
        case .quickAdd: "Quick add"
        case .food: "Food"
        case .drink: "Drink"
        case .supplements: "Supplements"
        case .workout: "Workout"
        case .habits: "Habits"
        case .weight: "Weight"
        case .cycle: "Cycle"
        }
    }

    var symbol: String {
        switch self {
        case .photo: "camera"
        case .quickAdd: "bolt"
        case .food: "fork.knife"
        case .drink: "waterbottle"
        case .supplements: "pills"
        case .workout: "dumbbell"
        case .habits: "checkmark"
        case .weight: "scalemass"
        case .cycle: CycleCopy.symbol
        }
    }

    /// The type colour; `nil` is neutral (Photo, Habits, Weight).
    var hue: Color? {
        switch self {
        case .food: VESSColor.calories
        case .quickAdd: VESSColor.carbs
        case .drink: VESSColor.water
        case .supplements: VESSColor.fat
        case .workout: VESSColor.activity
        case .cycle: VESSColor.cycle
        case .photo, .habits, .weight: nil
        }
    }
}

/// The type carousel under the Add sheet's nav bar (21, 22). It snaps; the
/// centred tile is the selection, with its name under it in the type
/// colour. Every tile is 72 pt and scales down to 0.78 (opacity 0.85) with
/// its distance from the centre, continuously while dragging. Tapping a
/// tile springs it to the centre. The selection changes once the scroll
/// settles, so the content swaps (and the haptic plays) once, not per tile
/// passed. The edges fade. Reduce Motion: no scaling or springs; the
/// centred tile is full size, the others 0.78.
///
/// VoiceOver hears one adjustable element ("Add type, Food, 3 of 9"). From
/// the AX3 text size the tiles give way to a row of text chips.
struct AddTypeCarousel: View {
    let types: [AddType]
    @Binding var selection: AddType

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Set to scroll a type to the centre once (tap, VoiceOver, opening).
    /// One-shot on purpose: a bound scroll position re-applies itself when
    /// the selection re-renders the view and pulls against the finger.
    @State private var scrollRequest: ScrollRequest?
    @State private var width: CGFloat = 0
    /// The tile at the centre; becomes the selection when the scroll settles.
    @State private var centred: AddType?
    /// Off until the first layout has scrolled to the selection: that
    /// layout asks for a target too, from the first tile.
    @State private var isReady = false

    /// Each tile sits in an equal slot, so snapping is exact: 10 pt beside
    /// the centred tile, 18 pt between the smaller ones.
    private static let slot: CGFloat = VESSAddTypeTile.size + 2
    private static let minScale: CGFloat = 0.78
    private static let minOpacity: Double = 0.85

    var body: some View {
        Group {
            if dynamicTypeSize >= .accessibility3 {
                textRow
            } else {
                tiles
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Add type")
        .accessibilityValue(Text("\(Text(selection.title)), \(index(of: selection) + 1) of \(types.count)"))
        .accessibilityAdjustableAction { direction in
            let index = index(of: selection)
            switch direction {
            case .increment: if index + 1 < types.count { selectNow(types[index + 1]) }
            case .decrement: if index > 0 { selectNow(types[index - 1]) }
            @unknown default: break
            }
        }
        .accessibilityIdentifier("add.types")
    }

    private var tiles: some View {
        let slot = Self.slot, minScale = Self.minScale, minOpacity = Self.minOpacity
        let reduceMotion = reduceMotion
        return VStack(spacing: VESSSpacing.xs) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(types, id: \.self) { type in
                            let isSelected = type == selection
                            Button { tap(type) } label: {
                                VESSAddTypeTile(systemImage: type.symbol, hue: type.hue)
                                    // 0 at the centre, 1 a slot or more away.
                                    .visualEffect { content, proxy in
                                        let t: CGFloat
                                        if reduceMotion {
                                            t = isSelected ? 0 : 1
                                        } else {
                                            let bounds = proxy.bounds(of: .scrollView) ?? .zero
                                            let midX = proxy.frame(in: .scrollView).midX
                                            t = min(abs(midX - bounds.midX) / slot, 1)
                                        }
                                        return content
                                            .scaleEffect(1 - (1 - minScale) * t)
                                            .opacity(1 - (1 - minOpacity) * Double(t))
                                    }
                                    .frame(width: slot, height: VESSAddTypeTile.size)
                                    .contentShape(Rectangle())
                                    // Reduce Motion: the size swap is instant.
                                    .transaction { if reduceMotion { $0.animation = nil } }
                            }
                            .buttonStyle(.plain)
                            .id(type)
                        }
                    }
                    .scrollTargetLayout()
                }
                // Snaps to whole slots and reports where it will land the moment
                // the finger lifts, so the selection doesn't wait for the
                // deceleration to finish.
                .scrollTargetBehavior(SlotSnapping(slot: slot) { index in
                    land(on: index)
                })
                .scrollIndicators(.hidden)
                // (width − tile) / 2 on both sides, so the first and last tiles
                // can sit in the centre too.
                .contentMargins(.horizontal, margin, for: .scrollContent)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .onScrollGeometryChange(for: Int.self) { geometry in
                    Int(((geometry.contentOffset.x + geometry.contentInsets.leading) / slot).rounded())
                } action: { _, index in
                    centred = types[min(max(index, 0), types.count - 1)]
                }
                .onScrollPhaseChange { _, phase in
                    // Fallback: whatever is centred once everything stops.
                    if isReady, phase == .idle, let centred, centred != selection { selection = centred }
                }
                .mask {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1),
                    ], startPoint: .leading, endPoint: .trailing)
                }
                .onChange(of: scrollRequest) { _, request in
                    guard let request else { return }
                    withAnimation(request.animated && !reduceMotion ? VESSMotion.addTileScroll : nil) {
                        proxy.scrollTo(request.type, anchor: .center)
                    }
                }
                .onAppear {
                    proxy.scrollTo(selection, anchor: .center)
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        centred = selection
                        isReady = true
                    }
                }
                // A selection made elsewhere (VoiceOver, the text row) re-centres.
                .onChange(of: selection) { _, new in
                    guard new != centred else { return }
                    scrollRequest = ScrollRequest(type: new, animated: true)
                }
            }

            // The name crossfades to the new type and its colour.
            ZStack {
                Text(selection.title)
                    .vessTextStyle(.bodyMStrong)
                    .foregroundStyle(selection.hue ?? VESSColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .id(selection)
                    .transition(.opacity)
            }
            .animation(reduceMotion ? VESSMotion.addSwapReduced : VESSMotion.addLabel, value: selection)
        }
        // Once per settled change. The chips of the text row play their own.
        .vessHaptic(.selection, trigger: selection)
    }

    /// AX3 and up: the names as chips, bleeding off the edges.
    private var textRow: some View {
        ScrollViewReader { proxy in
            VESSBleedingRow {
                HStack(spacing: VESSSpacing.xs) {
                    ForEach(types, id: \.self) { type in
                        VESSChip(title: type.title, isSelected: type == selection) { selection = type }
                            .id(type)
                    }
                }
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, new in proxy.scrollTo(new, anchor: .center) }
        }
    }

    /// (width − slot) / 2 on both sides.
    private var margin: CGFloat { max(0, (width - Self.slot) / 2) }

    /// The tile a swipe will settle on: selected as the finger lifts.
    private func land(on index: Int) {
        guard isReady else { return }
        let type = types[min(max(index, 0), types.count - 1)]
        Task { @MainActor in
            centred = type
            if type != selection { selection = type }
        }
    }

    private func index(of type: AddType) -> Int {
        types.firstIndex(of: type) ?? 0
    }

    /// Springs the tile to the centre and selects it.
    private func tap(_ type: AddType) {
        guard type != selection else { return }
        selectNow(type)
    }

    /// Tap and VoiceOver: centre the tile (with the spring) and select it.
    private func selectNow(_ type: AddType) {
        scrollRequest = ScrollRequest(type: type, animated: true)
        centred = type
        selection = type
    }

    private struct ScrollRequest: Equatable {
        let id = UUID()
        let type: AddType
        let animated: Bool
    }
}

/// Snaps the carousel to whole slots (one tile centred) and reports the
/// slot it will land on as soon as the target is known. The target's x is
/// measured from the first tile (the margins aren't part of it), so slot n
/// is centred at x = n × slot.
private struct SlotSnapping: ScrollTargetBehavior {
    let slot: CGFloat
    let onLanding: (Int) -> Void

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard slot > 0 else { return }
        let index = max(0, (target.rect.minX / slot).rounded())
        target.rect.origin.x = index * slot
        onLanding(Int(index))
    }
}
