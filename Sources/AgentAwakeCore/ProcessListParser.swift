import Foundation

public enum ProcessListParser {
    /// Parses output from `ps -axo pid=,ppid=,command=`.
    public static func parse(_ output: String) -> [ProcessRecord] {
        output.split(whereSeparator: { $0.isNewline }).compactMap { rawLine in
            let fields = rawLine.split(
                maxSplits: 2,
                omittingEmptySubsequences: true,
                whereSeparator: { $0.isWhitespace }
            )

            guard fields.count == 3,
                  let pid = Int32(fields[0]),
                  let parentPID = Int32(fields[1]) else {
                return nil
            }

            return ProcessRecord(
                pid: pid,
                parentPID: parentPID,
                commandLine: String(fields[2])
            )
        }
    }
}
