import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The UMEVA wordmark, drawn as UMEVΛ: five stroked letters in a 592 × 100
/// box (stroke 5, miter joins, butt caps; `Redesign/Brand/umeva-wordmark-ink.svg`).
/// The Λ has no crossbar on purpose, mirroring the V. The stroke scales with
/// the frame; the colour comes from the foreground style.
struct UMEVAWordmarkShape: Shape {
    static let viewBox = CGSize(width: 592, height: 100)
    static let lineWidth: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var letters = Path()
        // U
        letters.move(to: CGPoint(x: 2.5, y: 0))
        letters.addLine(to: CGPoint(x: 2.5, y: 65))
        letters.addArc(center: CGPoint(x: 35, y: 65), radius: 32.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        letters.addLine(to: CGPoint(x: 67.5, y: 0))
        // M
        letters.move(to: CGPoint(x: 127.5, y: 100))
        letters.addLine(to: CGPoint(x: 127.5, y: 2.5))
        letters.addLine(to: CGPoint(x: 170, y: 70))
        letters.addLine(to: CGPoint(x: 212.5, y: 2.5))
        letters.addLine(to: CGPoint(x: 212.5, y: 100))
        // E: stem and three bars
        letters.move(to: CGPoint(x: 272.5, y: 0)); letters.addLine(to: CGPoint(x: 272.5, y: 100))
        letters.move(to: CGPoint(x: 270, y: 2.5)); letters.addLine(to: CGPoint(x: 330, y: 2.5))
        letters.move(to: CGPoint(x: 270, y: 50)); letters.addLine(to: CGPoint(x: 325, y: 50))
        letters.move(to: CGPoint(x: 270, y: 97.5)); letters.addLine(to: CGPoint(x: 330, y: 97.5))
        // V
        letters.move(to: CGPoint(x: 385, y: 0)); letters.addLine(to: CGPoint(x: 423, y: 97.5)); letters.addLine(to: CGPoint(x: 461, y: 0))
        // Λ
        letters.move(to: CGPoint(x: 516, y: 100)); letters.addLine(to: CGPoint(x: 554, y: 2.5)); letters.addLine(to: CGPoint(x: 592, y: 100))
        let stroked = letters.strokedPath(StrokeStyle(lineWidth: Self.lineWidth, lineCap: .butt, lineJoin: .miter))
        return stroked.applying(UMEVABrandGeometry.fit(Self.viewBox, in: rect))
    }
}

/// The monogram: one Λ in a 100 × 100 box, stroke 4.
struct UMEVAMonogramShape: Shape {
    static let viewBox = CGSize(width: 100, height: 100)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 22, y: 80))
        path.addLine(to: CGPoint(x: 50, y: 18))
        path.addLine(to: CGPoint(x: 78, y: 80))
        let stroked = path.strokedPath(StrokeStyle(lineWidth: 4, lineCap: .butt, lineJoin: .miter))
        return stroked.applying(UMEVABrandGeometry.fit(Self.viewBox, in: rect))
    }
}

nonisolated enum UMEVABrandGeometry {
    /// Scales a view box to fit `rect`, centred, keeping its proportions.
    static func fit(_ box: CGSize, in rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width / box.width, rect.height / box.height)
        let x = rect.minX + (rect.width - box.width * scale) / 2
        let y = rect.minY + (rect.height - box.height * scale) / 2
        return CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale)
    }
}

/// The wordmark at a given width (its height follows, 592 : 100). Read as
/// "UMEVA" by VoiceOver.
struct UMEVAWordmark: View {
    /// At the top of the brand screens (B02, B04).
    static let headerWidth: CGFloat = 122

    var width: CGFloat = 150

    var body: some View {
        UMEVAWordmarkShape()
            .frame(width: width, height: width * UMEVAWordmarkShape.viewBox.height / UMEVAWordmarkShape.viewBox.width)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "UMEVA"))
            .accessibilityAddTraits(.isImage)
    }
}

/// The Λ monogram at a given size.
struct UMEVAMonogram: View {
    var size: CGFloat = 48

    var body: some View {
        UMEVAMonogramShape()
            .frame(width: size, height: size)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "UMEVA"))
            .accessibilityAddTraits(.isImage)
    }
}

/// Names of replaceable brand images. Screens check availability so final
/// assets can be dropped into the asset catalog without code changes.
enum VESSBrandAssets {
    /// Optional welcome-screen image. Only licensed imagery.
    static let welcomeHero = "WelcomeHero"
    /// Silk: pearl in Light, graphite in Dark.
    static let silk = "BrandSilk"
    /// Graphite silk in both appearances (UMEVA+ welcome).
    static let silkGraphite = "BrandSilkGraphite"

    static func isAvailable(_ name: String) -> Bool {
        #if canImport(UIKit)
        UIImage(named: name) != nil
        #else
        false
        #endif
    }
}

#Preview("Brand") {
    VStack(spacing: 40) {
        UMEVAWordmark(width: 240).foregroundStyle(VESSColor.brandInk)
        UMEVAMonogram(size: 80).foregroundStyle(VESSColor.brandInk)
    }
    .padding(40)
    .background(VESSColor.brandPearl)
}
