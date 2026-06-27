import SwiftUI

struct NumericPasswordDots: View {
    let count: Int
    let length: Int

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<length, id: \.self) { index in
                Circle()
                    .fill(index < count ? Color.primary : Color.secondary.opacity(0.22))
                    .frame(width: 14, height: 14)
            }
        }
        .accessibilityLabel("\(count) of \(length) digits entered")
    }
}

struct NumericPasswordKeypad: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void

    private let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"]
    ]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 22) {
                    ForEach(row, id: \.self) { digit in
                        digitButton(digit)
                    }
                }
            }

            HStack(spacing: 22) {
                Color.clear
                    .frame(width: 72, height: 72)

                digitButton("0")

                Button(action: onDelete) {
                    Image(systemName: "delete.left")
                        .font(.title3.weight(.semibold))
                        .frame(width: 72, height: 72)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete digit")
            }
        }
    }

    private func digitButton(_ digit: String) -> some View {
        Button {
            onDigit(digit)
        } label: {
            Text(digit)
                .font(.title.weight(.medium))
                .frame(width: 72, height: 72)
                .background(Color.secondary.opacity(0.10))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Digit \(digit)")
    }
}
