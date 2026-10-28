import Foundation
import TimingBombRunner

let input = FileHandle.standardInput.readDataToEndOfFile()
let output = await JSRunnerProtocol.handle(input: input)
FileHandle.standardOutput.write(output)
