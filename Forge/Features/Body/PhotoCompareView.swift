import SwiftData
import SwiftUI

/// Before/after comparison of two progress photos with a draggable reveal slider.
struct PhotoCompareView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<BodyWeightEntry> { $0.photo != nil }, sort: \BodyWeightEntry.date)
    private var entries: [BodyWeightEntry]

    @State private var beforeID: UUID?
    @State private var afterID: UUID?
    @State private var split: CGFloat = 0.5
    @State private var sideBySide = false
    @State private var choosing: Slot = .before

    enum Slot { case before, after }

    private var before: BodyWeightEntry? { entries.first { $0.id == beforeID } ?? entries.first }
    private var after: BodyWeightEntry? { entries.first { $0.id == afterID } ?? entries.last }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let before, let after, let b = image(before), let a = image(after) {
                    if sideBySide {
                        HStack(spacing: 8) {
                            labeled(b, entry: before, title: "Before")
                            labeled(a, entry: after, title: "After")
                        }
                        .padding(.horizontal)
                    } else {
                        slider(before: b, after: a)
                            .padding(.horizontal)
                    }
                    summary(before: before, after: after)
                }
                Picker("Mode", selection: $sideBySide) {
                    Text("Slider").tag(false)
                    Text("Side by Side").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Picker("Choosing", selection: $choosing) {
                        Text("Pick Before").tag(Slot.before)
                        Text("Pick After").tag(Slot.after)
                    }
                    .pickerStyle(.segmented)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(entries) { entry in
                                let isSelected = entry.id == (choosing == .before ? before?.id : after?.id)
                                Button {
                                    withAnimation(.snappy) {
                                        if choosing == .before { beforeID = entry.id } else { afterID = entry.id }
                                    }
                                } label: {
                                    VStack(spacing: 3) {
                                        if let ui = image(entry) {
                                            Image(uiImage: ui)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 60, height: 80)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(isSelected ? Theme.body : .clear, lineWidth: 3))
                                        }
                                        Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                                            .font(.caption2.weight(.semibold))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal)
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func image(_ entry: BodyWeightEntry) -> UIImage? {
        entry.photo.flatMap(UIImage.init(data:))
    }

    private func slider(before: UIImage, after: UIImage) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Image(uiImage: after)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: geo.size.height)
                    .clipped()
                Image(uiImage: before)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: geo.size.height)
                    .clipped()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: w * split)
                    }
                Rectangle()
                    .fill(.white)
                    .frame(width: 3)
                    .shadow(radius: 4)
                    .offset(x: w * split - 1.5)
                Image(systemName: "arrow.left.and.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(.white, in: Circle())
                    .shadow(radius: 4)
                    .offset(x: w * split - 18)
                VStack {
                    HStack {
                        tag("Before")
                        Spacer()
                        tag("After")
                    }
                    Spacer()
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                split = min(1, max(0, value.location.x / w))
            })
        }
        .aspectRatio(3 / 4, contentMode: .fit)
    }

    private func labeled(_ image: UIImage, entry: BodyWeightEntry, title: String) -> some View {
        VStack(spacing: 6) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topLeading) { tag(title).padding(8) }
            Text(entry.date.formatted(.dateTime.month(.abbreviated).day().year()))
                .font(.caption.weight(.semibold))
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: Capsule())
    }

    private func summary(before: BodyWeightEntry, after: BodyWeightEntry) -> some View {
        let days = Calendar.current.dateComponents([.day], from: before.date, to: after.date).day ?? 0
        let delta = after.weight - before.weight
        return HStack(spacing: 10) {
            summaryStat("\(Fmt.weight(before.weight)) → \(Fmt.weight(after.weight))", "lb")
            summaryStat(Fmt.signed(delta), "change")
            summaryStat("\(days)", "days apart")
        }
        .padding(.horizontal)
    }

    private func summaryStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.body.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
