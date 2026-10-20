import SwiftUI

/// Profile, minimal for Phase 1: who you are, your starting targets, and
/// deleting your data. Editing arrives with the full Profile phase.
struct ProfileView: View {
    @Environment(LocalStore.self) private var store
    @State private var confirmDelete = false
    @State private var showError = false

    var body: some View {
        NavigationStack {
            if let profile = store.profile {
                VESSScreen(title: "Profile") {
                    header(profile)
                    targets(profile)
                    bodyMetrics(profile)
                    privacy
                }
            }
        }
    }

    private func header(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            Text(profile.name.isEmpty ? String(localized: "You") : profile.name)
                .vessTextStyle(.detailTitle)
            Text(profile.goal.title)
                .vessTextStyle(.secondary)
        }
    }

    private func targets(_ profile: UserProfile) -> some View {
        let targets = profile.nutritionTargets
        return VESSSection(header: VESSSectionHeader(title: "Daily targets")) {
            VESSRowGroup {
                valueRow("Calories", value: "\(VESSFormat.calories(targets.calories)) kcal")
                valueRow("Protein", value: "\(VESSFormat.grams(targets.proteinGrams)) g")
                valueRow("Carbs", value: "\(VESSFormat.grams(targets.carbohydrateGrams)) g")
                valueRow("Fat", value: "\(VESSFormat.grams(targets.fatGrams)) g")
                valueRow("Water", value: "\(VESSFormat.liters(fromMilliliters: profile.waterTargetMilliliters)) L")
            }
            Text("Starting estimates from your answers, not medical advice.")
                .vessTextStyle(.label)
        }
    }

    private func bodyMetrics(_ profile: UserProfile) -> some View {
        VESSSection(header: VESSSectionHeader(title: "Body")) {
            VESSRowGroup {
                valueRow("Height", value: "\(VESSFormat.quantity(profile.heightCentimeters)) cm")
                valueRow("Weight", value: "\(VESSFormat.quantity(profile.weightKilograms)) kg")
                if let bmi = BodyMassIndex(weightKilograms: profile.weightKilograms, heightCentimeters: profile.heightCentimeters) {
                    valueRow("BMI", value: bmi.value.formatted(.number.precision(.fractionLength(1))))
                }
            }
            Text("BMI is shown for information only. It doesn't describe your health on its own.")
                .vessTextStyle(.label)
        }
    }

    private var privacy: some View {
        VESSSection(header: VESSSectionHeader(title: "Privacy and data")) {
            Text("Everything you log is stored on this iPhone.")
                .vessTextStyle(.secondary)
            Button("Delete all data", role: .destructive) {
                confirmDelete = true
            }
            .buttonStyle(.vessSecondary)
            .foregroundStyle(VESSColor.criticalText)
            .confirmationDialog("Delete all data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all data", role: .destructive, action: deleteAll)
            } message: {
                Text("Your profile, meals and drinks will be removed from this iPhone. This can't be undone.")
            }
            .vessErrorAlert(isPresented: $showError, retry: deleteAll)
        }
    }

    private func valueRow(_ title: LocalizedStringKey, value: String) -> some View {
        VESSRow(title: Text(title)) {
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(VESSColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func deleteAll() {
        do {
            try store.deleteAllData()
        } catch {
            showError = true
        }
    }
}

#Preview {
    ProfileView()
        .environment(LocalStore.preview())
}
