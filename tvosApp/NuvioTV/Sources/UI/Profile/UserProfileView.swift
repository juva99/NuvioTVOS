import SwiftUI

public struct UserProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @State private var showingAddProfile = false
    @State private var newProfileName = ""
    @State private var newProfilePin = ""
    @State private var newProfileAvatarId = ProfileAvatarCatalog.defaultId
    @FocusState private var focusedItem: String?

    private static let addProfileFocusId = "add_profile"

    public init(viewModel: ProfileViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationView {
            ZStack {
                ProfileBackground()

                VStack(spacing: 0) {
                    Spacer().frame(height: 162)

                    Text("Who's watching?")
                        .font(.custom("Inter-Bold", size: 62))
                        .foregroundColor(.white)

                    Spacer().frame(height: 14)

                    Text("Select a profile to continue")
                        .font(.custom("Inter-Regular", size: 28))
                        .foregroundColor(.white.opacity(0.6))

                    Spacer()

                    // Centered single row of profiles.
                    HStack(alignment: .top, spacing: 56) {
                        ForEach(viewModel.profiles, id: \.id) { profile in
                            ProfileCard(
                                profile: profile,
                                isFocused: focusedItem == profile.id
                            ) {
                                handleProfileSelection(profile)
                            }
                            .focused($focusedItem, equals: profile.id)
                        }

                        AddProfileButton(
                            isFocused: focusedItem == Self.addProfileFocusId
                        ) {
                            showingAddProfile = true
                        }
                        .focused($focusedItem, equals: Self.addProfileFocusId)
                    }
                    .padding(.horizontal, 80)
                    .frame(maxWidth: .infinity)

                    Spacer()

                    Spacer().frame(height: 56)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.isPinEntryVisible {
                    ProfilePinView(viewModel: viewModel)
                }
            }
            .sheet(isPresented: $showingAddProfile) {
                AddProfileView(
                    isPresented: $showingAddProfile,
                    name: $newProfileName,
                    pin: $newProfilePin,
                    avatarId: $newProfileAvatarId
                ) {
                    viewModel.createProfile(
                        name: newProfileName,
                        pin: newProfilePin.isEmpty ? nil : newProfilePin,
                        avatarId: newProfileAvatarId
                    )
                    newProfileName = ""
                    newProfilePin = ""
                    newProfileAvatarId = ProfileAvatarCatalog.defaultId
                }
            }
        }
    }

    private func handleProfileSelection(_ profile: Profile) {
        viewModel.requestSwitch(to: profile)
    }
}

/// Dark navy base with a soft blue glow toward the top, matching the brand.
private struct ProfileBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.10, blue: 0.18),
                    Color(red: 0.02, green: 0.03, blue: 0.06),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(red: 0.12, green: 0.30, blue: 0.55).opacity(0.55), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 950
            )
        }
        .ignoresSafeArea()
    }
}

struct ProfileCard: View {
    let profile: Profile
    let isFocused: Bool
    let action: () -> Void

    private let avatarSize: CGFloat = 180

    var body: some View {
        Button(action: action) {
            VStack(spacing: 18) {
                ProfileAvatarView(
                    avatarId: profile.avatarId,
                    size: avatarSize,
                    isFocused: isFocused
                )
                .overlay(alignment: .bottomTrailing) { badge }

                VStack(spacing: 4) {
                    Text(profile.name)
                        .font(.custom("Inter-Bold", size: 28))
                        .foregroundColor(isFocused ? .white : Color.white.opacity(0.6))
                        .lineLimit(1)

                    if profile.isAdmin {
                        Text("PRIMARY")
                            .font(.custom("Inter-Bold", size: 16))
                            .tracking(1.5)
                            .foregroundColor(ProfileAvatarStyle.accent)
                    }
                }
            }
            .scaleEffect(isFocused ? 1.12 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        }
        .buttonStyle(ProfilePlainButtonStyle())
        .focusEffectDisabled() // suppress tvOS default white halo; we draw our own ring
    }

    @ViewBuilder private var badge: some View {
        if profile.isAdmin {
            Image(systemName: "star.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .padding(11)
                .background(Circle().fill(ProfileAvatarStyle.accent))
                .offset(x: 4, y: 4)
        } else if profile.isPinProtected {
            Image(systemName: "lock.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .padding(12)
                .background(Circle().fill(Color.black.opacity(0.8)))
                .offset(x: 2, y: 2)
        }
    }
}

struct AddProfileButton: View {
    let isFocused: Bool
    let action: () -> Void

    private let avatarSize: CGFloat = 180

    var body: some View {
        Button(action: action) {
            VStack(spacing: 18) {
                Circle()
                    .fill(Color.white.opacity(isFocused ? 0.16 : 0.06))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 62, weight: .light))
                            .foregroundColor(isFocused ? .white : Color.white.opacity(0.55))
                    )
                    .overlay(
                        Circle()
                            .stroke(isFocused ? Color.white.opacity(0.86) : Color.white.opacity(0.3),
                                    lineWidth: isFocused ? 3 : 2)
                    )
                    .shadow(color: isFocused ? Color.white.opacity(0.3) : .clear, radius: 24)

                Text("Add Profile")
                    .font(.custom("Inter-Bold", size: 28))
                    .foregroundColor(isFocused ? .white : Color.white.opacity(0.6))
            }
            .scaleEffect(isFocused ? 1.12 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        }
        .buttonStyle(ProfilePlainButtonStyle())
        .focusEffectDisabled() // suppress tvOS default white halo; we draw our own ring
    }
}

/// Renders only the button's label so tvOS doesn't draw its default focused
/// platter -- the avatar's own scale + white ring is the sole focus visual.
private struct ProfilePlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

struct ProfileAvatar: Identifiable {
    let id: String
    let name: String
    let symbolName: String
    let colors: [Color]
}

enum ProfileAvatarCatalog {
    static let defaultId = "default"

    static let avatars: [ProfileAvatar] = [
        ProfileAvatar(
            id: defaultId,
            name: "Nova",
            symbolName: "sparkles",
            colors: [Color(red: 0.98, green: 0.45, blue: 0.78), Color(red: 0.44, green: 0.32, blue: 0.94)]
        ),
        ProfileAvatar(
            id: "orbit",
            name: "Orbit",
            symbolName: "moon.stars.fill",
            colors: [Color(red: 0.18, green: 0.60, blue: 0.93), Color(red: 0.08, green: 0.20, blue: 0.52)]
        ),
        ProfileAvatar(
            id: "arcade",
            name: "Arcade",
            symbolName: "gamecontroller.fill",
            colors: [Color(red: 0.16, green: 0.78, blue: 0.58), Color(red: 0.03, green: 0.36, blue: 0.34)]
        ),
        ProfileAvatar(
            id: "cinema",
            name: "Cinema",
            symbolName: "film.fill",
            colors: [Color(red: 0.94, green: 0.24, blue: 0.20), Color(red: 0.50, green: 0.08, blue: 0.18)]
        ),
        ProfileAvatar(
            id: "bolt",
            name: "Bolt",
            symbolName: "bolt.fill",
            colors: [Color(red: 1.0, green: 0.70, blue: 0.20), Color(red: 0.93, green: 0.31, blue: 0.18)]
        ),
        ProfileAvatar(
            id: "heart",
            name: "Heart",
            symbolName: "heart.fill",
            colors: [Color(red: 1.0, green: 0.42, blue: 0.58), Color(red: 0.65, green: 0.10, blue: 0.30)]
        ),
        ProfileAvatar(
            id: "music",
            name: "Music",
            symbolName: "music.note",
            colors: [Color(red: 0.38, green: 0.72, blue: 1.0), Color(red: 0.20, green: 0.32, blue: 0.78)]
        ),
        ProfileAvatar(
            id: "leaf",
            name: "Leaf",
            symbolName: "leaf.fill",
            colors: [Color(red: 0.39, green: 0.80, blue: 0.42), Color(red: 0.08, green: 0.42, blue: 0.26)]
        )
    ]

    static func avatar(for id: String?) -> ProfileAvatar {
        avatars.first(where: { $0.id == id }) ?? avatars[0]
    }

    static func symbolName(for id: String?) -> String {
        avatar(for: id).symbolName
    }
}

struct ProfileAvatarView: View {
    let avatarId: String
    var size: CGFloat
    var isFocused: Bool = false

    private var avatar: ProfileAvatar {
        ProfileAvatarCatalog.avatar(for: avatarId)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: avatar.colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: avatar.symbolName)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 3)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke(Color.white.opacity(isFocused ? 0.86 : 0.28), lineWidth: isFocused ? 3 : 1)
        )
        .shadow(color: isFocused ? Color.white.opacity(0.3) : .black.opacity(0.24), radius: isFocused ? 24 : 10, x: 0, y: 8)
    }
}

/// Stable avatar color fallback for older profile surfaces.
enum ProfileAvatarStyle {
    static let accent = Color(red: 0.98, green: 0.67, blue: 0.12) // primary star / label

    static func color(for id: String) -> Color {
        ProfileAvatarCatalog.avatar(for: id).colors.first ?? .blue
    }
}

struct AddProfileView: View {
    @Binding var isPresented: Bool
    @Binding var name: String
    @Binding var pin: String
    @Binding var avatarId: String
    var onSave: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Profile Info")) {
                    TextField("Name", text: $name)
                    SecureField("PIN (Optional)", text: $pin)
                        .keyboardType(.numberPad)
                }

                Section(header: Text("Avatar")) {
                    ProfileAvatarPicker(selectedAvatarId: $avatarId)
                }

                Button("Save") {
                    onSave()
                    isPresented = false
                }
                .disabled(name.isEmpty)
            }
            .navigationTitle("Add Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

struct ProfileAvatarPicker: View {
    @Binding var selectedAvatarId: String

    private let columns = [
        GridItem(.fixed(118), spacing: 18),
        GridItem(.fixed(118), spacing: 18),
        GridItem(.fixed(118), spacing: 18),
        GridItem(.fixed(118), spacing: 18)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(ProfileAvatarCatalog.avatars) { avatar in
                Button {
                    selectedAvatarId = avatar.id
                } label: {
                    VStack(spacing: 9) {
                        ProfileAvatarView(
                            avatarId: avatar.id,
                            size: 76,
                            isFocused: avatar.id == selectedAvatarId
                        )

                        Text(avatar.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.82))
                            .lineLimit(1)
                    }
                    .frame(width: 118, height: 122)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(avatar.id == selectedAvatarId ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(avatar.id == selectedAvatarId ? 0.5 : 0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(avatar.name)
            }
        }
        .padding(.vertical, 8)
    }
}

struct ProfileAvatarPickerSheet: View {
    @Binding var isPresented: Bool
    let title: String
    @State private var selectedAvatarId: String
    let onSave: (String) -> Void

    init(isPresented: Binding<Bool>, title: String, selectedAvatarId: String, onSave: @escaping (String) -> Void) {
        _isPresented = isPresented
        self.title = title
        _selectedAvatarId = State(initialValue: selectedAvatarId.isEmpty ? ProfileAvatarCatalog.defaultId : selectedAvatarId)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(title)) {
                    ProfileAvatarPicker(selectedAvatarId: $selectedAvatarId)
                }

                Button("Save") {
                    onSave(selectedAvatarId)
                    isPresented = false
                }
            }
            .navigationTitle("Choose Avatar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}
