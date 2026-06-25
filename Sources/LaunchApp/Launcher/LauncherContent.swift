import SwiftUI

struct LauncherContent: View {
    @ObservedObject var state: AppState
    let layout: LaunchpadLayoutMetrics
    let columns: [GridItem]
    let gridHeight: CGFloat
    let showsPageControl: Bool
    let pageWidth: CGFloat
    let visibleItems: [LauncherItem]
    let pageCount: Int
    let pageSize: Int

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: layout.safeTopInset)

            LauncherSearchField(query: $state.query, state: state)
                .frame(height: layout.searchBarHeight)

            Spacer(minLength: layout.searchToGridGap)

            Group {
                if state.searchQuery.isEmpty, state.displayMode == .paged {
                    PagedGridView(
                        state: state,
                        layout: layout,
                        columns: columns,
                        pageWidth: pageWidth,
                        gridHeight: gridHeight,
                        visibleItems: visibleItems,
                        pageCount: pageCount,
                        pageSize: pageSize
                    )
                } else {
                    SearchResultsGrid(state: state, layout: layout, columns: columns, visibleItems: visibleItems)
                }
            }
            .frame(height: gridHeight)
            .coordinateSpace(name: "launcherGrid")
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { state.launcherGridFrame = $0 }

            if showsPageControl {
                Spacer(minLength: layout.gridToPagerGap)

                LauncherPageControl(
                    state: state,
                    pageCount: pageCount,
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
    let visibleItems: [LauncherItem]

    var body: some View {
        ScrollView {
            ZStack(alignment: .top) {
                LauncherDismissLayer {
                    LaunchLog.line("search empty tap dismiss")
                    state.dismissFromBackground()
                }

                LazyVGrid(columns: columns, spacing: layout.gridRowSpacing) {
                    ForEach(visibleItems) { item in
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
    @EnvironmentObject private var drag: DragModel
    let layout: LaunchpadLayoutMetrics
    let columns: [GridItem]
    let pageWidth: CGFloat
    let gridHeight: CGFloat
    let visibleItems: [LauncherItem]
    let pageCount: Int
    let pageSize: Int

    var body: some View {
        // While dragging, render the live preview order so the other icons reflow around the gap.
        let renderItems = state.isDraggingLauncherItem ? state.dragRenderItems : visibleItems
        ZStack(alignment: .topLeading) {
            ForEach(renderedPages, id: \.self) { page in
                let thisPageOffset = pageOffsetFor(page)
                ZStack(alignment: .top) {
                    if page == state.currentPage {
                        LauncherDismissLayer {
                            LaunchLog.line("page empty tap dismiss page=\(page)")
                            state.dismissFromBackground()
                        }
                    }

                    LazyVGrid(columns: columns, spacing: layout.gridRowSpacing) {
                        ForEach(items(forPage: page, in: renderItems, pageSize: pageSize)) { item in
                            LauncherItemView(
                                item: item,
                                state: state,
                                layout: layout,
                                pageOffset: thisPageOffset,
                                loadsIcons: shouldLoadIcons(for: page)
                            )
                        }
                    }
                    .padding(.horizontal, layout.horizontalPadding)
                }
                .frame(width: pageWidth, height: gridHeight, alignment: .top)
                .offset(x: thisPageOffset)
            }
        }
        .frame(width: pageWidth, alignment: .leading)
        .clipped()
        .animation(LaunchConstants.Animation.pageSnap, value: state.currentPage)
        .animation(LaunchConstants.Animation.iconLift, value: state.dragInsertionIndex)
        .frame(height: gridHeight)
    }

    private var renderedPages: [Int] {
        if state.isDraggingLauncherItem {
            return Array(0..<pageCount)
        }
        let range = max(0, state.currentPage - 1)...min(pageCount - 1, state.currentPage + 1)
        return Array(range)
    }

    private func pageOffsetFor(_ page: Int) -> CGFloat {
        CGFloat(page - state.currentPage) * pageWidth + drag.pageOffset
    }

    private func shouldLoadIcons(for page: Int) -> Bool {
        abs(page - state.currentPage) <= 1
    }

    private func items(forPage page: Int, in items: [LauncherItem], pageSize: Int) -> [LauncherItem] {
        Array(items.dropFirst(page * pageSize).prefix(pageSize))
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
    let pageCount: Int
    let selectPage: (Int) -> Void

    var body: some View {
        HStack(spacing: LaunchConstants.Launcher.pageDotSpacing) {
            ForEach(0..<pageCount, id: \.self) { page in
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
