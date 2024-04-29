import SwiftUI
import CoreImage

public extension Image {
  private static let context = CIContext(options: nil)
  
  init(ciImage: CIImage) {
    if let cgImage = Self.context.createCGImage(ciImage, from: ciImage.extent) {
      self.init(cgImage, scale: 1.0, orientation: .up, label: Text(""))
    } else {
      self.init(systemName: "questionmark")
    }
  }
}
