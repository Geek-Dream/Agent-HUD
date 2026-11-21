import SwiftUI
import UniformTypeIdentifiers

struct StarDragSource: View {
    static let typeIdentifier = UTType.utf8PlainText.identifier
    let isImportant: Bool
    let sessionID: String
    let model: HUDViewModel

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onDrag {
                model.suppressNextRowOpenByID(sessionID)
                model.beginImportantDrag(sessionID)
                return NSItemProvider(object: sessionID as NSString)
            } preview: {
                Image(systemName: "star.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(HUDTheme.important)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
            }
            .allowsHitTesting(isImportant)
    }
}

struct StarDropDelegate: DropDelegate {
    let isImportant: Bool
    let sessionID: String
    let model: HUDViewModel

    func dropEntered(info: DropInfo) {
        guard isImportant, model.draggedImportantSessionID != nil else { return }
        withAnimation(HUDMetrics.listAnimation) {
            model.updateImportantDrag(targetID: sessionID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: isImportant ? .move : .cancel)
    }

    func validateDrop(info: DropInfo) -> Bool {
        isImportant && model.draggedImportantSessionID != sessionID
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isImportant, model.draggedImportantSessionID != nil else { return false }
        model.updateImportantDrag(targetID: sessionID)
        model.endImportantDrag()
        return true
    }
}
