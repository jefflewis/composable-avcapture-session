import Foundation
import UIKit
import AVFoundation
import CoreImage
import CoreFoundation
import Dependencies
import DependenciesMacros
import OSLog

@DependencyClient
struct CameraFeed {
  var subscribe: () async throws -> (
    feed: AsyncStream<CIImage>,
    unsubscribe: () -> Void
  ) = {( feed: .never, unsubscribe: {} )}
}

extension CameraFeed: DependencyKey {
  static var liveValue = {
    var managers: Set<CameraManager> = []
    return Self {
      let manager = CameraManager()
      try await manager.start()
      managers.insert(manager)
      return (
        feed: manager.previewStream.stream,
        unsubscribe: { managers.remove(manager) }
      )
    }
  }()
}

public enum CameraManagerError: Error {
  case unauthorized, missingCamera, sessionConfiguration
}

class CameraManager: NSObject {
  private let captureSession = AVCaptureSession()
  private var deviceInput: AVCaptureDeviceInput?
  private var videoOutput: AVCaptureVideoDataOutput?
  private let systemPreferredCamera = AVCaptureDevice.default(for: .video)
  private var sessionQueue = DispatchQueue(label: "video.preview.session")
  private let imageContext = CIContext()
  private let logger = Logger(subsystem: "camera", category: "capture-session")
  
  let previewStream = AsyncStream.makeStream(
    of: CIImage.self,
    bufferingPolicy: .bufferingNewest(1)
  )
  
  private var isAuthorized: Bool {
    get async {
      let status = AVCaptureDevice.authorizationStatus(for: .video)
      
      // Determine if the user previously authorized camera access.
      var isAuthorized = status == .authorized
      
      // If the system hasn't determined the user's authorization status,
      // explicitly prompt them for approval.
      if status == .notDetermined {
        logger.debug("requesting access")
        isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
      }
      
      logger.debug("access is authorized \(isAuthorized, format: .truth)")
      
      return isAuthorized
    }
  }

  deinit {
    logger.debug("ending capture session")
    captureSession.stopRunning()
    previewStream.continuation.finish()
  }
  
  func start() async throws {
    logger.debug("starting capture session")
    try await configureSession()
    try await startSession()
  }
  
  private func configureSession() async throws {
    guard await isAuthorized else { throw CameraManagerError.unauthorized }
    
    guard let systemPreferredCamera,
          let deviceInput = try? AVCaptureDeviceInput(
            device: systemPreferredCamera
          )
    else { throw CameraManagerError.missingCamera }
    
    captureSession.beginConfiguration()
    defer { self.captureSession.commitConfiguration() }

    let videoOutput = AVCaptureVideoDataOutput()
    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.automaticallyConfiguresOutputBufferDimensions = false
    videoOutput.deliversPreviewSizedOutputBuffers = true
    videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
    
    guard captureSession.canAddInput(deviceInput) else {
      throw CameraManagerError.sessionConfiguration
    }
    
    captureSession.addInput(deviceInput)

    guard captureSession.canAddOutput(videoOutput) else {
      throw CameraManagerError.sessionConfiguration
    }

    captureSession.addOutput(videoOutput)
    
    videoOutput.connection(with: .video)?.videoOrientation = .portrait
    self.videoOutput = videoOutput
  }
  
  private func startSession() async throws{
    guard await isAuthorized else { throw CameraManagerError.unauthorized }
    
    captureSession.startRunning()
  }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ captureOutput: AVCaptureOutput,
    didDrop sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    logger.debug("dropped a frame")
  }
  
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    logger.trace("captured output")

    guard let imageBuffer = sampleBuffer.imageBuffer else { return }
    
    let image = CIImage(cvPixelBuffer: imageBuffer)
    previewStream.continuation.yield(image)
  }
}

#if canImport(UIKit)
extension UIDeviceOrientation {
  var cGImagePropertyOrientation: CGImagePropertyOrientation {
    switch self {
    case .portrait, .faceUp: return .right
    case .portraitUpsideDown, .faceDown: return .right
    case .landscapeLeft: return .up
    case .landscapeRight: return .down
    case .unknown: return .up
    @unknown default: return .up
    }
  }
}
#endif


#if os(iOS)
extension UIDeviceOrientation {
  var videoOrientation: AVCaptureVideoOrientation {
    // UIDeviceOrientation has reversed landscape left/right
    switch self {
    case .landscapeRight: return .landscapeLeft
    case .landscapeLeft: return .landscapeRight
    default: return .portrait
    }
  }
}
#endif
