import SwiftUI

struct GitHubSettingsView: View {
    @ObservedObject var githubService: GitHubService
    @State private var token = ""
    @State private var username = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss
    let entries: [HumanEntry]
    let documentsDirectory: URL
    
    var body: some View {
        VStack(spacing: 20) {
            if !githubService.isAuthenticated {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GitHub Token")
                        .font(.system(size: 13))
                    SecureField("Enter your GitHub token", text: $token)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Text("GitHub Username")
                        .font(.system(size: 13))
                    TextField("Enter your GitHub username", text: $username)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button("Authenticate") {
                        githubService.authenticate(token: token)
                        githubService.setUserName(username)
                    }
                    .disabled(token.isEmpty || username.isEmpty)
                }
            } else {
                VStack(spacing: 16) {
                    HStack {
                        Text("Status: \(githubService.syncStatus)")
                        Spacer()
                        if let lastSync = githubService.lastSyncDate {
                            Text("Last sync: \(lastSync, style: .relative)")
                        }
                    }
                    .font(.system(size: 13))
                    
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Sync Now") {
                            Task {
                                isLoading = true
                                do {
                                    try await githubService.syncEntries(entries: entries, documentsDirectory: documentsDirectory)
                                    alertMessage = "Sync completed successfully!"
                                } catch {
                                    alertMessage = "Sync failed: \(error.localizedDescription)"
                                }
                                showingAlert = true
                                isLoading = false
                            }
                        }
                        
                        Button("Logout") {
                            githubService.logout()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            
            Text("Your entries will be synced to a private GitHub repository named 'freewrite-entries'")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top)
            
            Button("Close") {
                dismiss()
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 400)
        .alert("Sync Status", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
} 