import SwiftUI

struct RecordDateTimeField: View {
    @Binding var date: Date
    var onOpen: () -> Void
    @State private var selectingDate = false

    var body: some View {
        Button {
            onOpen()
            selectingDate = true
        } label: {
            HStack {
                Text("Date & Time")
                Spacer()
                Text(dateTimeText)
                    .multilineTextAlignment(.trailing)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the date and time picker")
        .popover(isPresented: $selectingDate) {
            VStack(spacing: 0) {
                ScrollView {
                    DatePicker("Date & Time", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }
            }
            .padding(.bottom, 16)
            .frame(width: 320, height: 400)
            .presentationCompactAdaptation(.popover)
        }

    }

    private var dateTimeText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

}
