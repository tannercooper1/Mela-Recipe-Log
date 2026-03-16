import Foundation
import Combine
import SwiftUI
import zlib

class RecipeStore: ObservableObject {
    @Published var recipes: [Recipe] = []
    @Published var syncMessage: String? = nil
    @Published var lastSyncDate: Date? = nil

    private let fileName = "KitchenLog.json"
    private var fileURL: URL? { iCloudFileURL ?? localFileURL }
    private var metadataQuery: NSMetadataQuery?
    private var saveDebounceTask: Task<Void, Never>? = nil

    // MARK: - File URLs

    private var iCloudFileURL: URL? {
        FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            .appendingPathComponent(fileName)
    }

    private var localFileURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    // MARK: - Init

    init() {
        ensureDocumentsDirectory()
        load()
        startICloudObserver()
    }

    private func ensureDocumentsDirectory() {
        guard let iCloudURL = FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents") else { return }
        if !FileManager.default.fileExists(atPath: iCloudURL.path) {
            try? FileManager.default.createDirectory(at: iCloudURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Load & Save

    func load() {
        guard let url = fileURL else { return }
        if url == iCloudFileURL {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Recipe].self, from: data) else { return }
        DispatchQueue.main.async {
            self.recipes = decoded
            self.lastSyncDate = Date()
        }
    }

    func save() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self.writeToDisk()
        }
    }

    private func writeToDisk() async {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(recipes) else { return }
        do {
            try data.write(to: url, options: .atomic)
            await MainActor.run { self.lastSyncDate = Date() }
        } catch {
            await MainActor.run { self.syncMessage = "Save failed: \(error.localizedDescription)" }
        }
    }

    // MARK: - iCloud file observer

    private func startICloudObserver() {
        guard iCloudFileURL != nil else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, fileName)
        NotificationCenter.default.addObserver(self, selector: #selector(metadataQueryDidUpdate), name: .NSMetadataQueryDidUpdate, object: query)
        NotificationCenter.default.addObserver(self, selector: #selector(metadataQueryDidFinish), name: .NSMetadataQueryDidFinishGathering, object: query)
        query.start()
        self.metadataQuery = query
    }

    @objc private func metadataQueryDidFinish(_ notification: Notification) {
        metadataQuery?.disableUpdates(); load(); metadataQuery?.enableUpdates()
    }
    @objc private func metadataQueryDidUpdate(_ notification: Notification) {
        metadataQuery?.disableUpdates(); load(); metadataQuery?.enableUpdates()
    }

    // MARK: - Recipe mutations

    func addRecipe(_ recipe: Recipe) { recipes.append(recipe); save() }

    func deleteRecipe(_ recipe: Recipe) { recipes.removeAll { $0.id == recipe.id }; save() }

    func logCook(recipeID: UUID, entry: CookEntry) {
        guard let idx = recipes.firstIndex(where: { $0.id == recipeID }) else { return }
        recipes[idx].cooks.append(entry); save()
    }

    func deleteCook(recipeID: UUID, entryID: UUID) {
        guard let idx = recipes.firstIndex(where: { $0.id == recipeID }) else { return }
        recipes[idx].cooks.removeAll { $0.id == entryID }; save()
    }

    func updateRecipe(_ recipe: Recipe) {
        guard let idx = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        recipes[idx] = recipe; save()
    }

    // MARK: - Mela import

    @discardableResult
    @MainActor
    func importMelaFile(url: URL) async throws -> (imported: Int, skipped: Int) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()

        // Parse zip off the main actor
        let melasToImport: [MelaRecipe] = try await Task.detached(priority: .userInitiated) { [weak self] in
            guard self != nil else { return [] }
            print("[MelaImport] URL: \(url)")
            print("[MelaImport] ext: '\(ext)'")
            print("[MelaImport] fileExists: \(FileManager.default.fileExists(atPath: url.path))")
            if ext == "melarecipes" || ext == "zip" {
                return try RecipeStore.parseZipData(contentsOf: url)
            } else if ext == "melarecipe" {
                let data = try Data(contentsOf: url)
                guard let recipe = try? JSONDecoder().decode(MelaRecipe.self, from: data) else {
                    print("[MelaImport] JSON decode failed for single .melarecipe")
                    return []
                }
                return [recipe]
            }
            print("[MelaImport] Unrecognized extension: '\(ext)'")
            return []
        }.value

        var imported = 0
        var skipped = 0

        for mela in melasToImport {
            let isDuplicate = recipes.contains {
                ($0.melaID != nil && $0.melaID == mela.id) ||
                $0.name.lowercased() == mela.title.lowercased()
            }
            if isDuplicate {
                skipped += 1
            } else {
                recipes.append(Recipe(from: mela))
                imported += 1
            }
        }

        if imported > 0 { save() }
        syncMessage = "\(imported) imported, \(skipped) already in log"
        return (imported, skipped)
    }

    /// ZIP64-aware parser using the central directory — the correct way to navigate
    /// large ZIP files where local headers may have 0xFFFFFFFF placeholder sizes.
    private static func parseZipData(contentsOf url: URL) throws -> [MelaRecipe] {
        let data = try Data(contentsOf: url)
        print("[MelaImport] ZIP data size: \(data.count) bytes")
        guard data.count >= 22,
              data[0] == 0x50, data[1] == 0x4B else {
            print("[MelaImport] Not a ZIP (bad magic)")
            return []
        }

        // --- Locate End of Central Directory (EOCD) ---
        // Search backward for PK\x05\x06, allowing for an optional comment.
        var eocd = -1
        let searchFrom = max(0, data.count - 65558)
        for i in stride(from: data.count - 22, through: searchFrom, by: -1) {
            guard data[i] == 0x50, data[i+1] == 0x4B,
                  data[i+2] == 0x05, data[i+3] == 0x06 else { continue }
            let commentLen = Int(data.u16(at: i + 20))
            if i + 22 + commentLen == data.count { eocd = i; break }
        }
        guard eocd >= 0 else {
            print("[MelaImport] EOCD not found")
            return []
        }

        var cdOffset = Int(data.u32(at: eocd + 16))
        var cdSize   = Int(data.u32(at: eocd + 12))

        // Check for ZIP64 EOCD locator (PK\x06\x07) immediately before the EOCD.
        if eocd >= 20 {
            let loc = eocd - 20
            if data[loc] == 0x50, data[loc+1] == 0x4B,
               data[loc+2] == 0x06, data[loc+3] == 0x07 {
                let z64Off = Int(truncatingIfNeeded: data.u64(at: loc + 8))
                if z64Off + 56 <= data.count,
                   data[z64Off] == 0x50, data[z64Off+1] == 0x4B,
                   data[z64Off+2] == 0x06, data[z64Off+3] == 0x06 {
                    cdSize   = Int(truncatingIfNeeded: data.u64(at: z64Off + 40))
                    cdOffset = Int(truncatingIfNeeded: data.u64(at: z64Off + 48))
                    print("[MelaImport] ZIP64 central directory: offset=\(cdOffset) size=\(cdSize)")
                }
            }
        }

        guard cdOffset >= 0, cdOffset + cdSize <= data.count else {
            print("[MelaImport] Central directory out of bounds")
            return []
        }

        // --- Parse Central Directory ---
        var melas: [MelaRecipe] = []
        var pos = cdOffset
        var entryCount = 0

        while pos + 46 <= cdOffset + cdSize {
            guard data[pos] == 0x50, data[pos+1] == 0x4B,
                  data[pos+2] == 0x01, data[pos+3] == 0x02 else { break }

            let compression      = data.u16(at: pos + 10)
            var compressedSize   = Int(data.u32(at: pos + 20))
            var uncompressedSize = Int(data.u32(at: pos + 24))
            var localOffset      = Int(data.u32(at: pos + 42))
            let nameLen          = Int(data.u16(at: pos + 28))
            let extraLen         = Int(data.u16(at: pos + 30))
            let commentLen       = Int(data.u16(at: pos + 32))
            let entrySize        = 46 + nameLen + extraLen + commentLen

            let nameStart  = pos + 46
            guard nameStart + nameLen <= data.count else { break }
            let name = String(bytes: data[nameStart..<(nameStart + nameLen)], encoding: .utf8) ?? ""
            entryCount += 1

            // Parse ZIP64 extra field if any size/offset field is 0xFFFFFFFF.
            if compressedSize == Int(UInt32.max) || uncompressedSize == Int(UInt32.max) || localOffset == Int(UInt32.max) {
                let extraStart = nameStart + nameLen
                let extraEnd   = min(extraStart + extraLen, data.count)
                var ep = extraStart
                while ep + 4 <= extraEnd {
                    let eid = data.u16(at: ep)
                    let esz = Int(data.u16(at: ep + 2))
                    if eid == 0x0001 {
                        var fp = ep + 4
                        if uncompressedSize == Int(UInt32.max), fp + 8 <= ep + 4 + esz {
                            uncompressedSize = Int(truncatingIfNeeded: data.u64(at: fp)); fp += 8
                        }
                        if compressedSize == Int(UInt32.max), fp + 8 <= ep + 4 + esz {
                            compressedSize = Int(truncatingIfNeeded: data.u64(at: fp)); fp += 8
                        }
                        if localOffset == Int(UInt32.max), fp + 8 <= ep + 4 + esz {
                            localOffset = Int(truncatingIfNeeded: data.u64(at: fp))
                        }
                        break
                    }
                    ep += 4 + esz
                }
            }

            if name.lowercased().hasSuffix(".melarecipe"), compressedSize > 0 {
                print("[MelaImport] Entry \(entryCount): '\(name)' compression=\(compression) size=\(compressedSize)")
                guard localOffset + 30 <= data.count else {
                    print("[MelaImport]   -> local header OOB"); pos += entrySize; continue
                }
                let localNameLen  = Int(data.u16(at: localOffset + 26))
                let localExtraLen = Int(data.u16(at: localOffset + 28))
                let dataStart = localOffset + 30 + localNameLen + localExtraLen
                let dataEnd   = dataStart + compressedSize
                guard dataEnd <= data.count else {
                    print("[MelaImport]   -> data OOB"); pos += entrySize; continue
                }

                let entryData = Data(data[dataStart..<dataEnd])
                let rawData: Data
                if compression == 8 {
                    rawData = Self.inflateRaw(entryData) ?? entryData
                } else {
                    rawData = entryData
                }

                if let recipe = try? JSONDecoder().decode(MelaRecipe.self, from: rawData) {
                    print("[MelaImport]   -> decoded: '\(recipe.title)'")
                    melas.append(recipe)
                } else {
                    let preview = String(data: rawData.prefix(200), encoding: .utf8) ?? "<non-UTF8>"
                    print("[MelaImport]   -> JSON FAILED. Preview: \(preview)")
                }
            }

            pos += entrySize
        }

        print("[MelaImport] Total entries: \(entryCount), decoded: \(melas.count)")
        return melas
    }

    // MARK: - Stats

    var stats: AppStats {
        let totalCooks = recipes.reduce(0) { $0 + $1.cooks.count }
        let allRatings = recipes.flatMap { $0.cooks.filter { $0.rating > 0 }.map(\.rating) }
        let avgRating: Double? = allRatings.isEmpty ? nil : Double(allRatings.reduce(0, +)) / Double(allRatings.count)
        let mostCooked = recipes.filter { !$0.cooks.isEmpty }.map { (recipe: $0, count: $0.cooks.count) }.sorted { $0.count > $1.count }.prefix(5).map { $0 }
        let recentCooks = recipes.flatMap { r in r.cooks.map { (recipe: r, entry: $0) } }.sorted { $0.entry.date > $1.entry.date }.prefix(10).map { $0 }
        return AppStats(totalRecipes: recipes.count, totalCooks: totalCooks, averageRating: avgRating, mostCooked: mostCooked, recentCooks: recentCooks)
    }
}

// MARK: - Raw deflate decompression (ZIP compression method 8)

private extension RecipeStore {
    /// Decompresses raw DEFLATE data (RFC 1951) as stored in ZIP files.
    /// `NSData.decompressed(using: .zlib)` requires RFC 1950 (header + Adler-32 trailer)
    /// and silently fails on raw deflate, so we use zlib's inflateInit2 with a negative
    /// window size to enable raw inflate mode.
    static func inflateRaw(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        return data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = src.baseAddress else { return nil }
            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer(mutating: srcBase.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(data.count)
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
            defer { inflateEnd(&stream) }
            var result = Data()
            var buf = [UInt8](repeating: 0, count: 65536)
            var status: Int32 = Z_OK
            repeat {
                let written = buf.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
                    stream.next_out = dst.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(dst.count)
                    status = inflate(&stream, Z_SYNC_FLUSH)
                    return dst.count - Int(stream.avail_out)
                }
                if written > 0 { result.append(contentsOf: buf.prefix(written)) }
            } while status == Z_OK
            return status == Z_STREAM_END ? result : nil
        }
    }
}

// MARK: - Data helpers

private extension Data {
    func u16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
    func u32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) | (UInt32(self[offset+1]) << 8) |
        (UInt32(self[offset+2]) << 16) | (UInt32(self[offset+3]) << 24)
    }
    func u64(at offset: Int) -> UInt64 {
        UInt64(u32(at: offset)) | (UInt64(u32(at: offset + 4)) << 32)
    }
}
