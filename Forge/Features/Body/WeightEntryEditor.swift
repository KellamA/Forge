import PhotosUI
import SwiftData
import SwiftUI

struct WeightEntryEditor: View {
    let entry: BodyWeightEntry?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var entries: [BodyWeightEntry]
    @AppStorage(SettingsKey.healthSaveWeight) private var saveToHealth = true

    @State private var weight: Double = 0
    @State private var date = Date()
    @State private var bodyFat: Double = 0
    @State private var note = ""
    @State private var photo: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var confirmDelete = false
    @FocusState private var weightFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            WeightInput(value: $weight)
                                .focused($weightFocused)
                            Text("lb")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            ForEach([-1.0, -0.2, 0.2, 1.0], id: \.self) { step in
                                Button {
                                    weight = max(0, (weight + step).rounded(toPlaces: 1))
                                } label: {
                                    Text(step > 0 ? "+\(Fmt.weight(step))" : "−\(Fmt.weight(-step))")
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.subtleFill, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .sensoryFeedback(.selection, trigger: weight)
                            }
                        }
                        if let last = entries.first(where: { $0.id != entry?.id }), weight > 0 {
                            let delta = weight - last.weight
                            Text("\(Fmt.signed(delta)) lb since \(Fmt.relativeDay(last.date).lowercased() == "today" ? "earlier today" : Fmt.relativeDay(last.date))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                }

                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now)
                    HStack {
                        Text("Body Fat")
                        Spacer()
                        NumericField(placeholder: "Optional", value: $bodyFat, alignment: .trailing)
                            .frame(width: 100)
                        Text("%").foregroundStyle(.secondary)
                    }
                    TextField("Note", text: $note)
                }

                Section {
                    if let photo, let image = UIImage(data: photo) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 320)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        Button("Remove Photo", role: .destructive) {
                            withAnimation { self.photo = nil }
                        }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(photo == nil ? "Choose from Library" : "Replace from Library", systemImage: "photo.on.rectangle")
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                    }
                } header: {
                    Text("Progress Photo")
                } footer: {
                    Text("Photos are stored privately in Forge and your iCloud.")
                }

                if entry != nil {
                    Section {
                        Button("Delete Weigh-in", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(entry == nil ? "Log Weight" : "Edit Weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(weight <= 0)
                }
            }
            .onAppear(perform: load)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        photo = ImageCompressor.compress(data)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    photo = ImageCompressor.compress(image)
                }
                .ignoresSafeArea()
            }
            .confirmationDialog("Delete this weigh-in?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let entry { context.delete(entry) }
                    try? context.save()
                    dismiss()
                }
            }
        }
    }

    private func load() {
        if let entry {
            weight = entry.weight
            date = entry.date
            bodyFat = entry.bodyFat
            note = entry.note
            photo = entry.photo
        } else {
            weight = entries.first?.weight ?? 0
            if weight == 0 { weightFocused = true }
        }
    }

    private func save() {
        let target: BodyWeightEntry
        if let entry {
            target = entry
        } else {
            target = BodyWeightEntry(weight: weight, date: date)
            context.insert(target)
        }
        target.weight = weight.rounded(toPlaces: 1)
        target.date = date
        target.bodyFat = bodyFat
        target.note = note
        target.photo = photo
        try? context.save()
        if entry == nil && saveToHealth {
            Task { await HealthKitManager.shared.save(weightEntry: target) }
        }
        dismiss()
    }
}

/// Big centered decimal input for weigh-ins.
private struct WeightInput: View {
    @Binding var value: Double
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("0", text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 60, weight: .bold, design: .rounded))
            .monospacedDigit()
            .focused($focused)
            .fixedSize()
            .onAppear { text = value > 0 ? Fmt.weight(value) : "" }
            .onChange(of: value) { _, v in
                if Double(text.replacingOccurrences(of: ",", with: ".")) != v { text = v > 0 ? Fmt.weight(v) : "" }
            }
            .onChange(of: text) { _, t in
                if let v = Double(t.replacingOccurrences(of: ",", with: ".")) { value = v } else if t.isEmpty { value = 0 }
            }
    }
}

enum ImageCompressor {
    static func compress(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return compress(image)
    }

    /// Downscales to at most 1600 px on the long edge and encodes as JPEG.
    static func compress(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 1600
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.78)
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
