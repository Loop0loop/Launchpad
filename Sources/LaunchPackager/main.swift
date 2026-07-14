import Foundation

do {
    let options = try PackagerOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    try LaunchpadPackager(variant: options.variant).run(options)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
