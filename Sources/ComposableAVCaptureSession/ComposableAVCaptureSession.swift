import ComposableArchitecture
import CoreImage
import SwiftUI
import OSLog


private enum CancelId {
  case cameraFeed
}

@Reducer
public struct CameraFeature {
  public init() {}
  
  private let logger = Logger(subsystem: "camera", category: "feature")
  @Dependency (CameraFeed.self) var cameraFeed
  
  @ObservableState
  public struct State: Equatable {
    public init(previewImage: CIImage? = nil, alert: AlertState<CameraFeature.State.Alert>? = nil) {
      self.previewImage = previewImage
      self.alert = alert
    }
    
    public var previewImage: CIImage?
    @Presents public var alert: AlertState<Alert>?
    
    public enum Alert: Equatable {
      case unauthorized, setup
    }
  }
  
  public enum Action {
    case previewFrameUpdate(CIImage)
    case cameraFeedTask
    case cameraError(CameraManagerError)
    case alert(PresentationAction<State.Alert>)
  }
  
  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        
      case let .previewFrameUpdate(previewImage):
        state.previewImage = previewImage
        return .none
      case .cameraFeedTask:
        return .run(operation: { send in
          let subscription = try await cameraFeed.subscribe()
          for await previewImage in subscription.feed {
            if Task.isCancelled {
              break
            }
            await send(.previewFrameUpdate(previewImage))
            NotificationCenter
              .default
              .post(name: .init("CameraFeedDidUpdate"), object: previewImage)
          }
          subscription.unsubscribe()
        }, catch: { error, send in
          if let error = error as? CameraManagerError {
            await send(.cameraError(error))
          } else {
            logger.error("\(error)")
          }
        })
        .cancellable(id: CancelId.cameraFeed)
      case .alert(_):
        return .none
      case let .cameraError(error):
        logger.error("\(error)")
        switch error {
        case .unauthorized:
          state.alert = .unauthorized()
        case .missingCamera:
          state.alert = .missingCamera()
        case .sessionConfiguration:
          state.alert = .sessionConfiguration()
        }
        return .none
      }
    }
  }

}

public struct CameraFeatureView: View {
  public init(
    store: StoreOf<CameraFeature> = Store(
      initialState: CameraFeature.State()
    ) { CameraFeature() },
    onFrameUpdated: @escaping (CIImage) async -> Void
  ) {
    self.onFrameUpdated = onFrameUpdated
    self.store = store
  }
  
  let onFrameUpdated: (CIImage) async -> Void
  @Perception.Bindable var store: StoreOf<CameraFeature>
  
  public var body: some View {
    let _ = Self._printChanges()
    WithPerceptionTracking {
      if let previewImage = store.previewImage {
        Image(ciImage: previewImage)
          .resizable()
          .scaledToFill()
          .ignoresSafeArea(.all)
          .alert($store.scope(state: \.alert, action: \.alert))
      } else {
        Color.black.ignoresSafeArea(.all)
          .alert($store.scope(state: \.alert, action: \.alert))
          .task { store.send(.cameraFeedTask) }
      }
    }
    
  }
}

extension AlertState where Action == CameraFeature.State.Alert {
  public static func unauthorized() -> Self {
    Self {
      TextState("Camera access unauthorized")
    } actions: {
      ButtonState(role: .cancel) {
        TextState("Ok")
      }
    } message: {
      TextState("Grant access to the camera in System Settings to allow camera usage")
    }
  }
  
  public static func missingCamera() -> Self {
    Self {
      TextState("Camera missing")
    } actions: {
      ButtonState(role: .cancel) {
        TextState("Ok")
      }
    } message: {
      TextState("No video camera found")
    }
  }
  
  public static func sessionConfiguration() -> Self {
    Self {
      TextState("Camera setup failed")
    } actions: {
      ButtonState(role: .cancel) {
        TextState("Ok")
      }
    } message: {
      TextState("There was an unexpected error setting up the camera. Please try again.")
    }
  }
}
