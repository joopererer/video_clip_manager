/// Search interaction state derived from the search box and the semantic
/// retrieval state held by `AppState`.
///
/// The v1.1 search box keeps the manual-trigger contract:
/// typing filters by keyword in real time, while Enter or the ✨ button runs
/// the AI semantic search. These helpers exist so the toolbar, the tabs and
/// the regression tests all agree on what the user should be told.
enum SearchMode {
  /// No query text: nothing is filtered and no AI search ran.
  idle,

  /// Query text present, matching by keyword only.
  keyword,

  /// AI semantic search is running for the current query.
  semanticLoading,

  /// AI semantic results are displayed for the current query.
  semanticResults,
}

SearchMode resolveSearchMode({
  required String query,
  required bool isSemanticSearching,
  required int semanticResultCount,
}) {
  if (query.trim().isEmpty) return SearchMode.idle;
  if (isSemanticSearching) return SearchMode.semanticLoading;
  if (semanticResultCount > 0) return SearchMode.semanticResults;
  return SearchMode.keyword;
}

bool isSemanticMode(SearchMode mode) =>
    mode == SearchMode.semanticLoading || mode == SearchMode.semanticResults;

/// Short badge label describing the current search mode.
String searchModeLabel(SearchMode mode, {int semanticResultCount = 0}) {
  switch (mode) {
    case SearchMode.idle:
    case SearchMode.keyword:
      return '关键词筛选';
    case SearchMode.semanticLoading:
      return 'AI 语义检索中';
    case SearchMode.semanticResults:
      return 'AI 语义结果 ($semanticResultCount 个)';
  }
}

/// The actionable hint shown next to the search box.
String searchActionHint(SearchMode mode) {
  switch (mode) {
    case SearchMode.idle:
    case SearchMode.keyword:
      return '按 Enter 或点击 ✨ 进行 AI 语义搜索';
    case SearchMode.semanticLoading:
      return '正在执行 AI 语义搜索，请稍候…';
    case SearchMode.semanticResults:
      return '已按相似度排序，按 Enter 可重新搜索';
  }
}

/// Whether the "press Enter / click ✨ to run the AI search" affordance still
/// applies. It stops applying once a search is running or already displayed.
bool showsSemanticTriggerHint(SearchMode mode) =>
    mode == SearchMode.idle || mode == SearchMode.keyword;

/// Result banner headline for the clips tab.
String semanticResultHeadline(String query, int count) =>
    'AI 语义搜索结果：「$query」 共 $count 个结果';

/// Formats a similarity score for display. Similarity only: never present it
/// as accuracy or confidence, and never re-derive the number.
String formatSemanticScore(double score) =>
    'Score: ${score.toStringAsFixed(3)}';
