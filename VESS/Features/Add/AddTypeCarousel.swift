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
/// colour. Tapping a tile scrolls it to the centre. The edges fade.
///
/// VoiceOver hears one adjustable element ("Add type, Food, 3 of 9"). From
/// the AX3 text size the tiles give way to a row of text chips.
struct AddTypeCarousel: View {
    let types: [AddType]
    @Binding var selection: AddType

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var position = ScrollPosition(idType: AddType.self)
    @State private var width: CGFloat = 0
    /// The tile at the centre while the user scrolls; selected when it settles.
    @State private var centred: AddType?
    @State private var isScrolling = false

    /// Each tile sits in a slot this wide (a 56 pt tile and a 10 pt gap).
    /// Slots are equal so snapping is exact; the tiles beside the larger
    /// selected one are nudged outwards instead.
    private static let slot: CGFloat = VESSAddTypeTile.size + gap
    private static let gap: CGFloat = 10
    private static let nudge = (VESSAddTypeTile.selectedSize - VESSAddTypeTile.size) / 2

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
            case .increment: if index + 1 < types.count { select(types[index + 1]) }
            case .decrement: if index > 0 { select(types[index - 1]) }
            @unknown default: break
            }
        }
        .accessibilityIdentifier("add.types")
    }

    private var tiles: some View {
        let selectedIndex = index(of: selection)
        return VStack(spacing: VESSSpacing.xs) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(types.enumerated()), id: \.element) { offset, type in
                        Button { select(type) } label: {
                            VESSAddTypeTile(systemImage: type.symbol, hue: type.hue, isSelected: type == selection)
                                .frame(width: Self.slot, height: VESSAddTypeTile.selectedSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: offset == selectedIndex ? 0 : (offset < selectedIndex ? -Self.nudge : Self.nudge))
                        .id(type)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition($position, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            // Margins that let the first and last tiles reach the centre.
            .contentMargins(.horizontal, max(0, (width - Self.slot) / 2), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onScrollGeometryChange(for: Int.self) { geometry in
                Int(((geometry.contentOffset.x + geometry.contentInsets.leading) / Self.slot).rounded())
            } action: { _, index in
                centred = types[min(max(index, 0), types.count - 1)]
            }
            .onScrollPhaseChange { _, phase in
                isScrolling = phase != .idle
                // A swipe selects the tile it settles on.
                if phase == .idle, let centred, centred != selection { selection = centred }
            }
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            }
            .animation(reduceMotion ? nil : VESSMotion.selection, value: selection)
            .onAppear { position.scrollTo(id: selection, anchor: .center) }
            .onChange(of: selection) { _, new in
                guard !isScrolling else { return }
                withAnimation(reduceMotion ? nil : VESSMotion.selection) { position.scrollTo(id: new, anchor: .center) }
            }

            Text(selection.title)
                .vessTextStyle(.bodyMStrong)
                .foregroundStyle(selection.hue ?? VESSColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
        // The chips of the text row play their own.
        .vessHaptic(.selection, trigger: selection)
    }

    /// AX3 and up: the names as chips, bleeding off the edges.
    private var textRow: some View {
        ScrollViewReader { proxy in
            VESSBleedingRow {
                HStack(spacing: VESSSpacing.xs) {
                    ForEach(types, id: \.self) { type in
                        VESSChip(title: type.title, isSelected: type == selection) { select(type) }
                            .id(type)
                    }
                }
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, new in proxy.scrollTo(new, anchor: .center) }
        }
    }

    private func index(of type: AddType) -> Int {
        types.firstIndex(of: type) ?? 0
    }

    private func select(_ type: AddType) {
        isScrolling = false
        selection = type
    }
}
