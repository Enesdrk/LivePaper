import Foundation

public struct DisplayVideoResolver {
    public init() {}

    public func resolve(
        displayIDs: [UInt32],
        explicitAssignments: [DisplayAssignment],
        preferredVideoPath: String?,
        catalogPaths: [String],
        isUsablePath: (String) -> Bool
    ) -> [UInt32: String] {
        var result: [UInt32: String] = [:]
        let explicitMap = Dictionary(uniqueKeysWithValues: explicitAssignments.map { ($0.displayID, $0.videoPath) })
        let preferredVideo = preferredVideoPath.flatMap { path -> String? in
            guard !path.isEmpty, isUsablePath(path) else { return nil }
            return path
        }

        for (index, displayID) in displayIDs.enumerated() {
            if let assigned = explicitMap[displayID], isUsablePath(assigned) {
                result[displayID] = assigned
                continue
            }

            if let preferredVideo {
                result[displayID] = preferredVideo
                continue
            }

            if !catalogPaths.isEmpty {
                result[displayID] = catalogPaths[index % catalogPaths.count]
            }
        }

        return result
    }
}

