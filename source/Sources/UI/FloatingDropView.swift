#if os(macOS)
import SwiftUI

/// Lightweight always-on-top drop target shown in the floating NSPanel.
struct FloatingDropView: View {
    @EnvironmentObject private var coordinator: ConversionCoordinator
    @EnvironmentObject private var pro: ProManager

    var body: some View {
        ZStack {
            HoloBackground()
            VStack(spacing: 11) {
                HStack(spacing: 8) {
                    BrandMark(size: 22)
                    BrandTitle().font(.subheadline.weight(.semibold))
                    Spacer()
                }
                DropZoneView(compact: true)
                DropNoticeBanner()
                QueueListView()
            }
            .padding(14)
        }
        .frame(minWidth: 320, minHeight: 300)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $coordinator.showProGate) {
            ProGateView().environmentObject(pro)
        }
    }
}
#endif
