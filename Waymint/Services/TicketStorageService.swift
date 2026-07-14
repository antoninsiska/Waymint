import Foundation
import UniformTypeIdentifiers

struct TicketStorageService {
    enum StorageError: Error {
        case documentsDirectoryUnavailable
    }

    func ticketsDirectory() throws -> URL {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw StorageError.documentsDirectoryUnavailable
        }

        let directory = documents.appending(path: "Tickets", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: directory.path()) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    func localURL(forImportedFile sourceURL: URL) throws -> URL {
        let directory = try ticketsDirectory()
        let destination = directory.appending(path: "\(UUID().uuidString)-\(sourceURL.lastPathComponent)")
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    func saveTicketData(_ data: Data, preferredExtension: String) throws -> URL {
        let directory = try ticketsDirectory()
        let destination = directory.appending(path: "\(UUID().uuidString).\(preferredExtension)")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    func deleteLocalFile(at path: String?) {
        guard let path else { return }
        try? FileManager.default.removeItem(at: URL(filePath: path))
    }
}
