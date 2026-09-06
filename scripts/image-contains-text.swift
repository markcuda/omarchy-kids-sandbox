import Foundation
import ImageIO
import Vision

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
  FileHandle.standardError.write(Data("image-contains-text: needs an image and required text\n".utf8))
  exit(2)
}

let imagePath = arguments[1]
let required = arguments.dropFirst(2).map { $0.lowercased() }
let imageURL = URL(fileURLWithPath: imagePath) as CFURL
guard let source = CGImageSourceCreateWithURL(imageURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
  FileHandle.standardError.write(Data("image-contains-text: cannot read image\n".utf8))
  exit(1)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false

do {
  try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
} catch {
  FileHandle.standardError.write(Data("image-contains-text: text recognition failed: \(error.localizedDescription)\n".utf8))
  exit(1)
}

let text = (request.results ?? [])
  .compactMap { $0.topCandidates(1).first?.string }
  .joined(separator: "\n")
  .lowercased()

guard required.allSatisfy({ text.contains($0) }) else {
  FileHandle.standardError.write(Data("image-contains-text: required text is not visible\n".utf8))
  exit(1)
}
