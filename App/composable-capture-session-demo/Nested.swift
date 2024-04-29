import ComposableArchitecture
import ComposableAVCaptureSession
import SwiftUI

private let readMe = """
  This screen demonstrates how `Reducer` bodies can recursively nest themselves.

  Tap "Add row" to add a row to the current screen's list. Tap the left-hand side of a row to edit \
  its name, or tap the right-hand side of a row to navigate to its own associated list of rows.
  """

@Reducer
struct NestedContainer {
  @Reducer(state: .equatable)
  enum Path {
    case nested(Nested)
  }
  
  @Reducer(state: .equatable)
  enum Destination {
    case nested(Nested)
  }
  
  @ObservableState
   struct State: Equatable {
     var path = StackState<Path.State>()
     var destination: Destination.State? = nil
   }
  
  enum Action {
    case goBackToScreen(id: StackElementID)
    case path(StackActionOf<Path>)
    case destination(PresentationAction<Destination>)
    case nestButtonTapped
    case popToRoot
  }
  
  var body: some Reducer<State, Action> {
      Reduce { state, action in
        switch action {
        case let .goBackToScreen(id):
          state.path.pop(to: id)
          return .none

        case .path(_):
          return .none

        case .popToRoot:
          state.path.removeAll()
          return .none
        case .destination(_):
          return .none
        case .nestButtonTapped:
          state.destination = .nested(.init())
          return .none
        }
      }
      .forEach(\.path, action: \.path)
    }
}

struct NestedContainerView: View {
  @Bindable var store: StoreOf<NestedContainer> = .init(
    initialState: NestedContainer.State(
      path: .init()
    )
  ) {
    NestedContainer()
  }
  
  var body: some View {
    NavigationStack(
      path: $store.scope(state: \.path, action: \.path)) {
        NavigationLink(
         "Start",
         state: NestedContainer.Path.State.nested(.init())
       )
      } destination: { store in
        
        switch store.case {
        case let .nested(nestedStore):
          NestedView(store: nestedStore)
        }
      }

    
  }
}

@Reducer
struct Nested {
  
  
  @Reducer(state: .equatable)
  enum Destination {
    case nested(Nested)
    case cameraFeature(CameraFeature)
  }
  
  @ObservableState
  struct State: Equatable, Identifiable {
    let id: UUID
    var name: String = ""
    var rows: IdentifiedArrayOf<State> = []
    @Presents var destination: Destination.State? = nil
    var currentFrame: CIImage? = nil

    init(id: UUID? = nil, name: String = "", rows: IdentifiedArrayOf<State> = []) {
      @Dependency(\.uuid) var uuid
      self.id = id ?? uuid()
      self.name = name
      self.rows = rows
    }
  }

  enum Action {
    case addRowButtonTapped
    case nameTextFieldChanged(String)
    case onDelete(IndexSet)
    case openCameraButtonTapped
    case closeCameraButtonTapped
    case cameraToggled(Bool)
    case destination(PresentationAction<Destination.Action>)
    case nestButtonTapped(Nested.State.ID)

    indirect case rows(IdentifiedActionOf<Nested>)
  }

  @Dependency(\.uuid) var uuid

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .addRowButtonTapped:
        state.rows.append(State(id: self.uuid()))
        return .none

      case let .nameTextFieldChanged(name):
        state.name = name
        return .none

      case let .onDelete(indexSet):
        state.rows.remove(atOffsets: indexSet)
        return .none

      case .rows:
        return .none
      case .openCameraButtonTapped:
        state.destination = .cameraFeature(.init())
        return .none
      case .closeCameraButtonTapped:
        state.destination = nil
        return .none
      case let .cameraToggled(isOpen):
        if isOpen, state.destination == nil {
          state.destination = .cameraFeature(.init())
        } else if !isOpen {
          state.destination = nil
        }
        return .none
      case let .destination(.presented(.cameraFeature(.previewFrameUpdate(previewFrame)))):
        state.currentFrame = previewFrame
        return .none
      case .destination:
        return .none
      case let .nestButtonTapped(id):
        guard let row = state.rows[id: id] else { return .none }
        state.destination = .nested(row)
        return .none
      }
    }
    .forEach(\.rows, action: \.rows) {
      Self()
    }
    .ifLet(\.$destination, action: \.destination)
//    ._printChanges()
  }
}

struct NestedView: View {
  @Bindable var store: StoreOf<Nested>

  var body: some View {
    WithPerceptionTracking {
      
    Form {
      Section {
        Text(readMe)
      }
      Section(content: {
        ForEach(store.scope(state: \.rows, action: \.rows)) { rowStore in
          @Bindable var rowStore = rowStore
          NavigationLink {
            NestedView(store: rowStore)
          } label: {
            HStack {
              TextField("Untitled", text: $rowStore.name.sending(\.nameTextFieldChanged))
              Text("Next")
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          }
        }
        .onDelete { store.send(.onDelete($0)) }
      }, header: {
        Text("Path Navigation")
      })
      
      Section(content: {
        ForEach(store.scope(state: \.rows, action: \.rows)) { rowStore in
          @Bindable var rowStore = rowStore
          
          Button(
            action: { store.send(.nestButtonTapped(rowStore.id)) },
            label: {
              TextField("Untitled", text: $rowStore.name.sending(\.nameTextFieldChanged))
              Text("Next")
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          )
        }
        .onDelete { store.send(.onDelete($0)) }


      }, header: {
        Text("Tree Navigation")
      })
    }
    .navigationTitle(store.name.isEmpty ? "Untitled" : store.name)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button("Open Camera", systemImage: "camera") {
          store.send(.openCameraButtonTapped)
        }
      }
      ToolbarItem(placement: .navigationBarTrailing) {
        Button(
          "Add row",
          systemImage: "plus"
        ) {
          store.send(.addRowButtonTapped)
        }
      }
    }
    .navigationDestination(
      item: $store.scope(
        state: \.destination?.nested,
        action: \.destination.nested
      )
    ) { nestedStore in
      WithPerceptionTracking {
        NestedView(store: nestedStore)
      }
      
    }
    .fullScreenCover(
      item: $store.scope(state: \.destination?.cameraFeature, action: \.destination.cameraFeature)) { cameraStore in
        WithPerceptionTracking {
        
          NavigationStack {
            WithPerceptionTracking {
              //                    CameraFeatureView(onFrameUpdated: { _ in })
              //                      .toolbar {
              //                        ToolbarItem(placement: .navigationBarTrailing) {
              //                          Button("Close") { store.send(.closeCameraButtonTapped) }
              //                        }
              //                      }
              
              CameraFeatureView(
                store: cameraStore,
                onFrameUpdated: { _ in }
              )
              .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                  Button("Close") { store.send(.closeCameraButtonTapped) }
                }
              }
            }
          }
          
          
        }
      }
    }
  }
}

#Preview {
  NavigationView {
    NestedView(
      store: Store(
        initialState: Nested.State(
          name: "Foo",
          rows: [
            Nested.State(
              name: "Bar",
              rows: [
                Nested.State()
              ]
            ),
            Nested.State(
              name: "Baz",
              rows: [
                Nested.State(name: "Fizz"),
                Nested.State(name: "Buzz"),
              ]
            ),
            Nested.State(),
          ]
        )
      ) {
        Nested()
      }
    )
  }
}
