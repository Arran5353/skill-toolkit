import Foundation

public struct Scanner {
    public struct Result: Equatable {
        public let items: [SkillItem]
        public let warnings: [ScanWarning]
    }

    /// Convenience wrapper over scan(...) using the standard ~/.claude layout. CatalogLoader calls scan(...) directly; kept for standalone use/tests.
    public static func scanDefault(projectDirs: [String]) -> Result {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return scan(
            userSkillsDir: "\(home)/.claude/skills",
            pluginsCacheDir: "\(home)/.claude/plugins/cache",
            projectDirs: projectDirs,
            includeBuiltins: true
        )
    }

    public static func scan(userSkillsDir: String, pluginsCacheDir: String,
                            projectDirs: [String], includeBuiltins: Bool) -> Result {
        var items: [SkillItem] = []
        var warnings: [ScanWarning] = []

        // 1. user top-level skills: <userSkillsDir>/<name>/SKILL.md
        scanSkillDirs(in: userSkillsDir, scope: .user, pluginName: nil,
                      items: &items, warnings: &warnings)

        // 2. plugin skills + commands: <cache>/<marketplace>/<plugin>/<ver>/skills|commands
        for marketplace in subdirectories(of: pluginsCacheDir) {
            for plugin in subdirectories(of: marketplace.path) {
                let pluginName = plugin.lastPathComponent
                for version in subdirectories(of: plugin.path)
                    .sorted(by: { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }) {
                    scanSkillDirs(in: version.appendingPathComponent("skills").path,
                                  scope: .user, pluginName: pluginName,
                                  items: &items, warnings: &warnings)
                    scanCommandFiles(in: version.appendingPathComponent("commands").path,
                                     scope: .user, pluginName: pluginName,
                                     items: &items, warnings: &warnings)
                }
            }
        }

        // 3. project-level: <project>/.claude/skills, <project>/.claude/commands
        for project in projectDirs {
            let url = URL(fileURLWithPath: project)
            let parent = url.deletingLastPathComponent().lastPathComponent
            let name = parent.isEmpty ? url.lastPathComponent : "\(parent)/\(url.lastPathComponent)"
            scanSkillDirs(in: "\(project)/.claude/skills", scope: .project(name),
                          pluginName: nil, items: &items, warnings: &warnings)
            scanCommandFiles(in: "\(project)/.claude/commands", scope: .project(name),
                             pluginName: nil, items: &items, warnings: &warnings)
        }

        // 4. built-ins
        if includeBuiltins { items.append(contentsOf: BuiltinCommands.load()) }

        // 5. deduplicate by id, keeping highest-version (first-seen) entry
        var seenIDs = Set<String>()
        items = items.filter { seenIDs.insert($0.id).inserted }

        return Result(items: items, warnings: warnings)
    }

    // MARK: - Helpers

    private static func subdirectories(of path: String) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private static func scanSkillDirs(in dir: String, scope: SourceScope, pluginName: String?,
                                      items: inout [SkillItem], warnings: inout [ScanWarning]) {
        for sub in subdirectories(of: dir) {
            let file = sub.appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let dirName = sub.lastPathComponent
            appendParsed(file: file.path, fallbackName: dirName, kind: .skill,
                         scope: scope, pluginName: pluginName, items: &items, warnings: &warnings)
        }
    }

    private static func scanCommandFiles(in dir: String, scope: SourceScope, pluginName: String?,
                                         items: inout [SkillItem], warnings: inout [ScanWarning]) {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for entry in entries where entry.hasSuffix(".md") {
            let path = "\(dir)/\(entry)"
            let base = (entry as NSString).deletingPathExtension
            appendParsed(file: path, fallbackName: base, kind: .command,
                         scope: scope, pluginName: pluginName, items: &items, warnings: &warnings)
        }
    }

    private static func appendParsed(file: String, fallbackName: String, kind: ItemKind,
                                     scope: SourceScope, pluginName: String?,
                                     items: inout [SkillItem], warnings: inout [ScanWarning]) {
        let text: String
        if let read = try? String(contentsOfFile: file, encoding: .utf8) {
            text = read
            if text.isEmpty {
                warnings.append(ScanWarning(filePath: file, message: "Empty file"))
            }
        } else {
            text = ""
            warnings.append(ScanWarning(filePath: file, message: "Could not read file"))
        }
        let parsed = FrontmatterParser.parse(text)
        if parsed.frontmatter.isEmpty && !text.isEmpty {
            warnings.append(ScanWarning(filePath: file, message: "No frontmatter found"))
        }
        let name = parsed.frontmatter["name"] ?? fallbackName
        let item = SkillItem(
            name: name, kind: kind, scope: scope, pluginName: pluginName,
            description: parsed.frontmatter["description"] ?? "",
            body: parsed.body, filePath: file,
            insertText: Injector.defaultInsertText(kind: kind, name: name)
        )
        items.append(item)
    }
}
