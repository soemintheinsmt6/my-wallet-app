import SwiftUI
import WalletDomain

/// A scroll view with pull to refresh that draws the wallet mark in place of the system spinner:
/// the wallet fills in with the accent color as it is pulled, bounces while the refresh runs, and
/// turns into a green checkmark as it finishes.
///
/// On iOS it installs its own `UIRefreshControl` rather than using `.refreshable`, whose spinner
/// cannot be restyled. That also puts opening and closing in this view's hands. Under
/// `.refreshable`, the dashboard redrawing as fresh data arrived could close the control the moment
/// it was released, with the refresh still running out of sight, or leave it open with nothing
/// running. The system control still does the pulling, keeps its feel and its place above the
/// large title, and has its spinner made clear. Elsewhere than iOS it is a plain refreshable
/// scroll view.
struct WalletRefreshScrollView<Content: View>: View {
    private let action: @MainActor @Sendable () async -> Void
    private let content: Content
    /// Not observed here: the pull changes it every frame, and only the indicator needs to redraw.
    @State private var state = WalletRefreshState()

    init(action: @escaping @MainActor @Sendable () async -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    var body: some View {
        #if os(iOS)
        ScrollView {
            content.background(WalletRefreshControlBridge(state: state, action: action))
        }
        #else
        ScrollView { content }
            .refreshable { await action() }
        #endif
    }
}

/// How long the control stays open for a refresh that has not finished. A refresh normally takes
/// well under a second; one still waiting goes on, and its data lands when it finishes.
private let longestRefreshWait = Duration.seconds(6)

/// True if `work` finished within `limit`. It is never cancelled: it goes on either way.
@MainActor
private func waitFor(_ work: Task<Void, Never>, upTo limit: Duration) async -> Bool {
    await withCheckedContinuation { continuation in
        let first = FirstResult(continuation)
        Task { await work.value; first.resume(true) }
        Task { try? await Task.sleep(for: limit); first.resume(false) }
    }
}

/// Resumes a continuation with whichever result comes first, and ignores the other.
@MainActor
private final class FirstResult {
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }

    func resume(_ value: Bool) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

/// What the refresh mark draws from: how far the pull has come, reported by the scroll view, and
/// where the refresh is, reported by the refresh action.
@MainActor
final class WalletRefreshState: ObservableObject {
    enum Phase { case idle, refreshing, finished }

    /// 0 to 1: how far toward the point that refreshes the content has been pulled.
    @Published var progress: CGFloat = 0
    @Published var phase = Phase.idle
}

/// The mark itself, in the refresh control's place.
struct WalletRefreshIndicator: View {
    @ObservedObject var state: WalletRefreshState
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch state.phase {
            case .idle: pulling
            case .refreshing: refreshing
            case .finished:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .font(.system(size: 26, weight: .semibold))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(duration: 0.35, bounce: 0.4), value: state.phase)
        .sensoryFeedback(.impact(weight: .light), trigger: state.phase) { _, phase in phase == .refreshing }
        .accessibilityHidden(true)
    }

    /// A faint wallet, filled from the bottom up by the pull, growing in as it appears. The faint
    /// one is the same filled symbol, not the outline: the outline's strokes fall outside the
    /// filled shape, and showed around it as gray edges once the fill was complete.
    private var pulling: some View {
        Image(systemName: WalletSymbols.walletFill)
            .foregroundStyle(tint.opacity(0.22))
            .overlay {
                Image(systemName: WalletSymbols.walletFill)
                    .foregroundStyle(tint)
                    .mask {
                        GeometryReader { proxy in
                            Rectangle()
                                .frame(height: proxy.size.height * state.progress)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
            }
            .scaleEffect(0.6 + 0.4 * state.progress)
            .opacity(min(1, state.progress * 2))
    }

    @ViewBuilder private var refreshing: some View {
        if reduceMotion {
            Image(systemName: WalletSymbols.walletFill)
                .foregroundStyle(tint)
                .symbolEffect(.pulse)
        } else {
            PhaseAnimator([false, true]) { raised in
                Image(systemName: WalletSymbols.walletFill)
                    .foregroundStyle(tint)
                    .scaleEffect(raised ? 1.1 : 0.94)
                    .offset(y: raised ? -4 : 0)
                    .opacity(raised ? 1 : 0.75)
            } animation: { _ in
                .spring(duration: 0.4, bounce: 0.45)
            }
        }
    }
}

#if os(iOS)
import UIKit

/// Finds the scroll view this sits in and gives it a refresh control of its own: spinner made
/// clear, `WalletRefreshIndicator` drawn inside, fed by the scroll offset, and opened and closed
/// by this view alone.
private struct WalletRefreshControlBridge: UIViewRepresentable {
    let state: WalletRefreshState
    let action: @MainActor @Sendable () async -> Void
    /// The theme's accent: the indicator is hosted apart from the view tree the theme tints.
    @AppStorage(WalletPreferenceKeys.accent) private var accent = WalletAccent.system.rawValue

    private var tint: Color { WalletAccent(rawValue: accent)?.color ?? .accentColor }

    func makeUIView(context: Context) -> BridgeView { BridgeView(state: state, tint: tint, action: action) }

    func updateUIView(_ view: BridgeView, context: Context) { view.update(tint: tint, action: action) }

    final class BridgeView: UIView {
        /// How far a pull fills the wallet completely; about where the system control refreshes.
        private static let refreshDistance: CGFloat = 110

        private let state: WalletRefreshState
        private var action: @MainActor @Sendable () async -> Void
        private let control = UIRefreshControl()
        private let host: UIHostingController<WalletRefreshIndicator>
        private weak var scrollView: UIScrollView?
        private var offsetObservation: NSKeyValueObservation?
        private var refreshing: Task<Void, Never>?

        init(state: WalletRefreshState, tint: Color, action: @escaping @MainActor @Sendable () async -> Void) {
            self.state = state
            self.action = action
            host = UIHostingController(rootView: WalletRefreshIndicator(state: state, tint: tint))
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            host.safeAreaRegions = []
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            control.tintColor = .clear
            control.addSubview(host.view)
            control.addTarget(self, action: #selector(beginRefresh), for: .valueChanged)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach()
        }

        func update(tint: Color, action: @escaping @MainActor @Sendable () async -> Void) {
            self.action = action
            host.rootView = WalletRefreshIndicator(state: state, tint: tint)
            attach()
        }

        @objc private func beginRefresh() {
            guard refreshing == nil else { return }
            refreshing = Task { [weak self] in
                await self?.refresh()
                self?.refreshing = nil
            }
        }

        private func refresh() async {
            state.phase = .refreshing
            let work = Task { [action] in await action() }
            if await waitFor(work, upTo: longestRefreshWait) {
                state.phase = .finished
                // Long enough to see the checkmark before the control closes.
                try? await Task.sleep(for: .milliseconds(600))
            } else {
                state.phase = .idle
            }
            control.endRefreshing()
            settle()
            // Back to the empty wallet once the control has closed over the checkmark.
            try? await Task.sleep(for: .milliseconds(400))
            if state.phase == .finished { state.phase = .idle }
        }

        /// Scrolls back to the top if ending the refresh left the content pulled down. Under a large
        /// title, `endRefreshing` removes the control's space from the inset but can leave the offset
        /// where it was, a blank band above the title that stays until the next touch.
        private func settle() {
            guard let scrollView, !scrollView.isDragging else { return }
            let rest = -scrollView.adjustedContentInset.top
            guard scrollView.contentOffset.y < rest - 0.5 else { return }
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: rest), animated: true)
        }

        private func attach() {
            guard window != nil else { return }
            if scrollView == nil {
                var ancestor = superview
                while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
                guard let found = ancestor as? UIScrollView else { return }
                scrollView = found
                offsetObservation = found.observe(\.contentOffset) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.scrollDidChange() }
                }            }
            scrollDidChange()
        }

        private func scrollDidChange() {
            guard let scrollView else { return }
            // Checked on every change, in case SwiftUI clears the scroll view's control.
            if scrollView.refreshControl !== control { scrollView.refreshControl = control }
            if host.view.frame != control.bounds { host.view.frame = control.bounds }
            let pull = max(0, -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top))
            let progress = min(1, pull / Self.refreshDistance)
            if state.progress != progress { state.progress = progress }
        }
    }
}
#endif
