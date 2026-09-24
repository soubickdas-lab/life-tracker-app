import SwiftUI

/// The door. Nothing to paste and no link to find — an email and a password,
/// the same ones the web app uses.
struct SignInView: View {
    @Environment(Store.self) private var store

    @State private var making = false
    @State private var email = ""
    @State private var password = ""
    @State private var problem: String?
    @State private var working = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ZStack {
            UI.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 20)
                Panel(padding: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(LinearGradient(colors: [UI.accent, UI.mint],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 52, height: 52)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Life Tracker")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("Your day, your habits, and the long things — in one place.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Picker("", selection: $making) {
                            Text("Sign in").tag(false)
                            Text("Create account").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: making) { _, _ in problem = nil }

                        VStack(alignment: .leading, spacing: 10) {
                            TextField("you@example.com", text: $email)
                                .textContentType(.emailAddress)
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: .email)
                                #if os(iOS)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif

                            SecureField("at least 8 characters", text: $password)
                                .textContentType(making ? .newPassword : .password)
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: .password)
                                .onSubmit(go)
                        }

                        if let problem {
                            Text(problem)
                                .font(.system(size: 13))
                                .foregroundStyle(UI.rose)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button(action: go) {
                            HStack(spacing: 8) {
                                if working { ProgressView().controlSize(.small) }
                                Text(making ? "Create account" : "Sign in")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(working || !looksReady)

                        if making {
                            Text("New accounts wait to be let in before their day shows up.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: 380)
                .padding(.horizontal, 22)
                Spacer(minLength: 20)
            }
        }
        .onAppear { focus = .email }
    }

    private var looksReady: Bool {
        email.contains("@") && password.count >= 8
    }

    private func go() {
        guard looksReady, !working else { return }
        working = true
        problem = nil
        Task {
            let address = email.trimmingCharacters(in: .whitespaces).lowercased()
            problem = making
                ? await store.signUp(email: address, password: password)
                : await store.signIn(email: address, password: password)
            working = false
            if problem == nil { password = "" }
        }
    }
}

/// Shown when the account exists but has not been let in yet.
struct WaitingView: View {
    @Environment(Store.self) private var store
    @State private var checking = false

    var body: some View {
        ZStack {
            UI.canvas.ignoresSafeArea()
            Panel(padding: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 30))
                        .foregroundStyle(UI.amber)
                    Text("Almost there")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Your account is made. Someone has to let it in before your day shows up here.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button(checking ? "Checking…" : "Check again") {
                            checking = true
                            Task { await store.checkDoor(); checking = false }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(checking)

                        Button("Sign out") { store.signOut() }
                    }
                }
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 22)
        }
    }
}

/// The owner account keeps nothing of its own — it only lets people in, and that
/// happens in the web app.
struct OwnerView: View {
    @Environment(Store.self) private var store

    var body: some View {
        ZStack {
            UI.canvas.ignoresSafeArea()
            Panel(padding: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "person.2.badge.key")
                        .font(.system(size: 30))
                        .foregroundStyle(UI.accent)
                    Text("Owner account")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("This one only lets people in. Open the web app to see who is waiting, and sign in with your own account here to track your day.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(store.email)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Button("Sign out") { store.signOut() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: 380)
            .padding(.horizontal, 22)
        }
    }
}
