import Foundation

class GitHubService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var syncStatus = "Not synced"
    @Published var lastSyncDate: Date?
    
    private var token: String?
    private let defaults = UserDefaults.standard
    private let tokenKey = "github_token"
    private let baseURL = "https://api.github.com"
    private let deletedFilesKey = "github_deleted_files"
    
    init() {
        self.token = defaults.string(forKey: tokenKey)
        self.isAuthenticated = token != nil
    }
    
    func authenticate(token: String) {
        self.token = token
        defaults.set(token, forKey: tokenKey)
        isAuthenticated = true
    }
    
    func logout() {
        self.token = nil
        defaults.removeObject(forKey: tokenKey)
        isAuthenticated = false
    }
    
    // Track a deleted file to be removed from GitHub during next sync
    func trackDeletedFile(filename: String) {
        var deletedFiles = getDeletedFiles()
        deletedFiles.append(filename)
        defaults.set(deletedFiles, forKey: deletedFilesKey)
    }
    
    // Get the list of files that were deleted locally
    private func getDeletedFiles() -> [String] {
        return defaults.stringArray(forKey: deletedFilesKey) ?? []
    }
    
    // Clear the list of deleted files after sync
    private func clearDeletedFiles() {
        defaults.removeObject(forKey: deletedFilesKey)
    }
    
    func syncEntries(entries: [HumanEntry], documentsDirectory: URL) async throws {
        guard let token = token else {
            throw NSError(domain: "GitHubService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Update sync status
        await MainActor.run {
            syncStatus = "Syncing..."
        }
        
        // Create repository if it doesn't exist
        try await createRepoIfNeeded()
        
        // Get all GitHub files first
        let repoFiles = try await getRepositoryFiles()
        let localFilenames = entries.map { $0.filename }
        
        // Determine which files need to be deleted (in repo but not local)
        let filesToDelete = repoFiles.filter { !localFilenames.contains($0) }
        let deletedFilesTracked = getDeletedFiles()
        
        // Sync each entry
        for entry in entries {
            let fileURL = documentsDirectory.appendingPathComponent(entry.filename)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            try await uploadFile(filename: entry.filename, content: content)
        }
        
        // Process deleted files
        let allFilesToDelete = Set(filesToDelete + deletedFilesTracked)
        for filename in allFilesToDelete {
            try await deleteFile(filename: filename)
        }
        
        // Clear the deleted files tracking
        clearDeletedFiles()
        
        // Update sync status
        await MainActor.run {
            syncStatus = "Synced"
            lastSyncDate = Date()
        }
    }
    
    private func getRepositoryFiles() async throws -> [String] {
        let url = URL(string: "\(baseURL)/repos/\(getUserName())/freewrite-entries/contents/")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return [] }
            
            if httpResponse.statusCode == 404 {
                return [] // Repository or folder doesn't exist yet
            }
            
            guard httpResponse.statusCode == 200,
                  let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            
            return jsonArray.compactMap { $0["name"] as? String }
        } catch {
            return [] // Handle errors by returning empty array
        }
    }
    
    private func deleteFile(filename: String) async throws {
        guard let sha = try await getFileSHA(filename: filename) else {
            return // File doesn't exist, nothing to delete
        }
        
        let url = URL(string: "\(baseURL)/repos/\(getUserName())/freewrite-entries/contents/\(filename)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let deleteData: [String: Any] = [
            "message": "Delete \(filename)",
            "sha": sha
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: deleteData)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "GitHubService", code: (response as? HTTPURLResponse)?.statusCode ?? 500,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to delete file"])
        }
    }
    
    private func createRepoIfNeeded() async throws {
        let url = URL(string: "\(baseURL)/user/repos")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let repoData = [
            "name": "freewrite-entries",
            "private": true,
            "description": "My Freewrite entries"
        ] as [String: Any]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: repoData)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return }
        
        if httpResponse.statusCode != 201 && httpResponse.statusCode != 422 { // 422 means repo already exists
            throw NSError(domain: "GitHubService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to create repository"])
        }
    }
    
    private func getFileSHA(filename: String) async throws -> String? {
        let url = URL(string: "\(baseURL)/repos/\(getUserName())/freewrite-entries/contents/\(filename)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            
            if httpResponse.statusCode == 404 {
                return nil // File doesn't exist yet
            }
            
            guard httpResponse.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sha = json["sha"] as? String else {
                return nil
            }
            
            return sha
        } catch {
            return nil // Handle any errors by assuming file doesn't exist
        }
    }
    
    private func uploadFile(filename: String, content: String) async throws {
        let url = URL(string: "\(baseURL)/repos/\(getUserName())/freewrite-entries/contents/\(filename)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let base64Content = Data(content.utf8).base64EncodedString()
        var fileData: [String: Any] = [
            "message": "Update \(filename)",
            "content": base64Content
        ]
        
        // Get the file's SHA if it exists
        if let sha = try await getFileSHA(filename: filename) {
            fileData["sha"] = sha
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: fileData)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 || httpResponse.statusCode == 200 else {
            throw NSError(domain: "GitHubService", code: (response as? HTTPURLResponse)?.statusCode ?? 500,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to upload file"])
        }
    }
    
    private func getUserName() -> String {
        // This would normally fetch the username from GitHub API
        // For now, we'll use a placeholder that the user can configure
        return defaults.string(forKey: "github_username") ?? ""
    }
    
    func setUserName(_ username: String) {
        defaults.set(username, forKey: "github_username")
    }
} 