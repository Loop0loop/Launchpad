import SwiftUI

struct LauncherContent: View {
    @ObservedObject var state: AppState
    let layout: LaunchpadLayoutMetrics
    let columns: [GridItem]
    let gridHeight: CGFloat
    let showsPageControl: Bool
    let pageWidth: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: layout.safeTopInset)

            LauncherSearchField(query: $state.query, state: state)
                .frame(height: layout.searchBarHeight)

            Spacer(minLength: layout.searchToGridGap)

            Group {
                if state.query.isEmpty, state.displayMode == .paged {
                    PagedGridView(
                        state: state,
                        layout: layout,
                        columns: columns,
                        pageWidth: pageWidth,
                        gridHeight: gridHeight
                    )
                } else {
                    SearchResultsGrid(state: state, layout: layout, columns: columns)
                }
            }
            .frame(height: gridHeight)
            .coordinateSpace(name: "launcherGrid")

            if showsPageControl {
                Spacer(minLength: layout.gridToPagerGap)

                LauncherPageControl(
                    state: state,
                    selectPage: state.selectPage
                )
                .frame(height: layout.pageControlHeight)
            }

            Spacer(minLength: layout.safeBottomInset)
        }
    }
}

struct SearchResultsGrid: View {
    @ObservedObject var state: AppState
    let layout: LaunchpadLayoutMetrics
    let columns: [GridItem]

    var body: some View {
        ScrollView {
            ZStack(alignment: .top) {
                LauncherDismissLayer {
                    LaunchLog.line("search empty tap dismiss")
                    state.dismissFromBackground()
                }

                LazyVGrid(columns: columns, spacing: layout.gridRowSpacing) {
                    ForEach(state.visibleItems) { item in
                        LauncherItemView(item: item, state: state, layout: layout, pageOffset: 0)
                    }
                }
                .padding(.horizontal, layout.horizontalPadding)
            }
            .frame(minHeight: layout.gridHeight(showsPageControl: false), alignment: .top)
        }
    }
}

struct PagedGridView: View {
    @ObservedObject var state: AppState
    let layout: LaunchpadLayoutMetrics
    let columns: [GridItem]
    let pageWidth: CGFloat
    let gridHeight: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<state.pageCount, id: \.self) { page in
                ZStack(alignment: .top) {
                    LauncherDismissLayer {
                        LaunchLog.line("page empty tap dismiss page=\(page)")
                        state.dismissFromBackground()
                    }

                    let thisPageOffset = pageOffset + CGFloat(page) * pageWidth
                    LazyVGrid(columns: columns, spacing: layout.gridRowSpacing) {
                        ForEach(state.items(forPage: page)) { item in
                            LauncherItemView(item: item, state: state, layout: layout, pageOffset: thisPageOffset)
                        }
                    }
                    .padding(.horizontal, layout.horizontalPadding)
                }
                .frame(width: pageWidth, height: gridHeight, alignment: .top)
            }
        }
        .offset(x: pageOffset)
        .frame(width: pageWidth, alignment: .leading)
        .clipped()
        .animation(LaunchConstants.Animation.pageSnap, value: state.currentPage)
        .frame(height: gridHeight)
    }

    private var pageOffset: CGFloat {
        -CGFloat(state.currentPage) * pageWidth + state.pageDragOffset
    }
}

struct LauncherDismissLayer: View {
    let action: () -> Void

    var body: some View {
        Color.black.opacity(0.0001)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

struct LauncherSearchField: View {
    @Binding var query: String
    @ObservedObject var state: AppState

    var body: some View {
        LauncherSearchBarRepresentable(text: $query, state: state) { bar in
            state.registerSearchBar(bar)
            if state.searchFocus.shouldFocusOnShow {
                DispatchQueue.main.async {
                    state.focusSearchField()
                }
            }
        }
        .frame(width: LaunchConstants.Launcher.searchWidth, height: LaunchConstants.Launcher.searchHeight)
        .frame(maxWidth: .infinity)
    }
}

struct LauncherPageControl: View {
    @ObservedObject var state: AppState
    let selectPage: (Int) -> Void

    var body: some View {
        HStack(spacing: LaunchConstants.Launcher.pageDotSpacing) {
            ForEach(0..<state.pageCount, id: \.self) { page in
                Circle()
                    .fill(page == state.currentPage ? .white : .white.opacity(LaunchConstants.Launcher.inactivePageOpacity))
                    .frame(
                        width: LaunchConstants.Launcher.pageDotSize,
                        height: LaunchConstants.Launcher.pageDotSize
                    )
                    .scaleEffect(page == state.currentPage ? LaunchConstants.Launcher.pageIndicatorActiveScale : 1)
                    .padding(6)
                    .contentShape(Rectangle())
                    .animation(LaunchConstants.Animation.fade, value: state.currentPage)
                    .onTapGesture {
                        LaunchLog.line("page dot tapped page=\(page)")
                        withAnimation(LaunchConstants.Animation.pageSnap) {
                            selectPage(page)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
