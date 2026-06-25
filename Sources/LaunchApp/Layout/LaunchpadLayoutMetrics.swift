import CoreGraphics

/// Screen-relative layout tuned to match native macOS Launchpad proportions.
struct LaunchpadLayoutMetrics {
    let size: CGSize
    var columns = LaunchConstants.Launcher.columns
    var rows = LaunchConstants.Launcher.rows

    var horizontalPadding: CGFloat {
        max(LaunchConstants.Launcher.minHorizontalPadding, size.width * LaunchConstants.Launcher.horizontalPaddingRatio)
    }

    /// Space above the search field (menu bar region).
    var safeTopInset: CGFloat {
        max(LaunchConstants.Launcher.minTopInset, size.height * LaunchConstants.Launcher.topInsetRatio)
            + LaunchConstants.Launcher.menuBarReserve
    }

    /// Space below page control (dock region).
    var safeBottomInset: CGFloat {
        max(LaunchConstants.Launcher.minBottomInset, size.height * LaunchConstants.Launcher.bottomInsetRatio)
    }

    var searchBarHeight: CGFloat {
        LaunchConstants.Launcher.searchHeight
    }

    var pageControlHeight: CGFloat {
        LaunchConstants.Launcher.pageControlHeight
    }

    var searchToGridGap: CGFloat {
        LaunchConstants.Launcher.searchToGridGap
    }

    var gridToPagerGap: CGFloat {
        LaunchConstants.Launcher.gridToPagerGap
    }

    /// Total height reserved at top for search chrome + gap before grid.
    var topChromeHeight: CGFloat {
        safeTopInset + searchBarHeight + searchToGridGap
    }

    /// Grid area between top and bottom chrome.
    func gridHeight(showsPageControl: Bool) -> CGFloat {
        let bottomChromeHeight = showsPageControl ? pageControlHeight + gridToPagerGap + safeBottomInset : safeBottomInset
        let available = size.height - topChromeHeight - bottomChromeHeight
        return max(available, 120)
    }

    var gridWidth: CGFloat {
        size.width - horizontalPadding * 2
    }

    var columnWidth: CGFloat {
        let columnCount = max(columns, 1)
        let totalSpacing = gridColumnSpacing * CGFloat(max(columnCount - 1, 0))
        return max((gridWidth - totalSpacing) / CGFloat(columnCount), 1)
    }

    var rowHeight: CGFloat {
        gridHeight(showsPageControl: true) / CGFloat(rows)
    }

    var iconSize: CGFloat {
        let fromColumn = columnWidth * LaunchConstants.Launcher.iconColumnScale
        let fromRow = rowHeight * LaunchConstants.Launcher.iconRowScale
        return min(max(min(fromColumn, fromRow), LaunchConstants.Launcher.minIconSize), LaunchConstants.Launcher.maxIconSize)
    }

    var gridColumnSpacing: CGFloat {
        LaunchConstants.Launcher.gridSpacing
    }

    var gridRowSpacing: CGFloat {
        max(LaunchConstants.Launcher.minGridRowSpacing, rowHeight - iconSize - LaunchConstants.Icon.labelHeight - LaunchConstants.Icon.spacing)
    }

    var labelWidth: CGFloat {
        min(columnWidth - 4, LaunchConstants.Icon.maxLabelWidth)
    }
}
