import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../utils/tag_utils.dart';
import 'tabs/clips_tab.dart';
import 'tabs/videos_tab.dart';
import 'tabs/playlists_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // 当tab切换时触发UI更新
    });
    _searchController.addListener(
      () => setState(() => _searchQuery = _searchController.text),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showTagFilterDialog() {
    final appState = context.read<AppState>();
    showDialog(
      context: context,
      builder: (context) {
        final allTags = appState.allTags;
        List<String> tempSelectedTags = List.from(appState.selectedTags);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Filter by Tags'),
              content: SizedBox(
                width: double.maxFinite,
                child: allTags.isEmpty
                    ? const Text('No tags available.')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: allTags.length,
                        itemBuilder: (context, index) {
                          final tag = allTags[index];
                          return CheckboxListTile(
                            title: buildTagText(tag),
                            value: tempSelectedTags.contains(tag),
                            onChanged: (isSelected) {
                              setDialogState(() {
                                if (isSelected == true) {
                                  tempSelectedTags.add(tag);
                                } else {
                                  tempSelectedTags.remove(tag);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    appState.setSelectedTags(tempSelectedTags);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRatingFilterDialog() {
    final appState = context.read<AppState>();
    int? tempSelectedRating = appState.selectedRating;
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Filter by Rating'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Select rating to filter by:'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      // 不过滤选项
                      ChoiceChip(
                        label: const Text('All Ratings'),
                        selected: tempSelectedRating == null,
                        onSelected: (selected) {
                          setDialogState(() {
                            tempSelectedRating = selected ? null : tempSelectedRating;
                          });
                        },
                      ),
                      // 无星级选项
                      ChoiceChip(
                        label: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_border, size: 16, color: Colors.grey),
                            Text(' No Rating'),
                          ],
                        ),
                        selected: tempSelectedRating == 0,
                        onSelected: (selected) {
                          setDialogState(() {
                            tempSelectedRating = selected ? 0 : null;
                          });
                        },
                      ),
                      // 1-5星选项
                      ...List.generate(5, (index) {
                        final rating = index + 1;
                        return ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ...List.generate(rating, (starIndex) => 
                                const Icon(Icons.star, size: 16, color: Colors.amber)
                              ),
                              Text(' $rating'),
                            ],
                          ),
                          selected: tempSelectedRating == rating,
                          onSelected: (selected) {
                            setDialogState(() {
                              tempSelectedRating = selected ? rating : null;
                            });
                          },
                        );
                      }),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    appState.setSelectedRating(tempSelectedRating);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showFavoriteFilterDialog() {
    final appState = context.read<AppState>();
    bool? tempSelectedFavorite = appState.selectedFavorite;
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Filter by Favorite'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Select favorite status to filter by:'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All Clips'),
                        selected: tempSelectedFavorite == null,
                        onSelected: (selected) {
                          setDialogState(() {
                            tempSelectedFavorite = selected ? null : tempSelectedFavorite;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.favorite, color: Colors.red),
                            SizedBox(width: 4),
                            Text('Favorites Only'),
                          ],
                        ),
                        selected: tempSelectedFavorite == true,
                        onSelected: (selected) {
                          setDialogState(() {
                            tempSelectedFavorite = selected ? true : null;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.favorite_border, color: Colors.grey),
                            SizedBox(width: 4),
                            Text('Not Favorites'),
                          ],
                        ),
                        selected: tempSelectedFavorite == false,
                        onSelected: (selected) {
                          setDialogState(() {
                            tempSelectedFavorite = selected ? false : null;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    appState.setSelectedFavorite(tempSelectedFavorite);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text('Video Clip Manager (${appState.currentDbPath})'),
        actions: [
          PopupMenuButton<int>(
            onSelected: (item) async {
              if (item == 0) {
                final result = await appState.importAndMergeClips();
                _showSnackBar(result);
              } else if (item == 1) {
                final result = await appState.switchDatabase();
                _showSnackBar(result);
              } else if (item == 2) {
                await appState.forceRefreshThumbnails();
                _showSnackBar("All thumbnails are being refreshed.");
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<int>(
                value: 0,
                child: Text('Import & Merge JSON'),
              ),
              const PopupMenuItem<int>(
                value: 1,
                child: Text('Switch Database'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<int>(
                value: 2,
                child: Text('Refresh All Thumbnails'),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.cut), text: 'Clips'),
            Tab(icon: Icon(Icons.movie), text: 'Original Videos'),
            Tab(icon: Icon(Icons.playlist_play), text: 'Playlists'),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 标签过滤 - 只在clips tab显示
                        if (_tabController.index == 0 && appState.selectedTags.isNotEmpty)
                          Chip(
                            label: Text('${appState.selectedTags.length}'),
                            onDeleted: () => appState.clearSelectedTags(),
                          ),
                        // 星级过滤 - 只在clips tab显示
                        if (_tabController.index == 0 && appState.selectedRating != null)
                          Chip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                appState.selectedRating == 0
                                    ? const Icon(Icons.star_border, size: 16, color: Colors.grey)
                                    : const Icon(Icons.star, size: 16, color: Colors.amber),
                                Text(appState.selectedRating == 0 ? 'No Rating' : '${appState.selectedRating}'),
                              ],
                            ),
                            onDeleted: () => appState.clearSelectedRating(),
                          ),
                        // 爱心收藏过滤 - 只在clips tab显示
                        if (_tabController.index == 0 && appState.selectedFavorite != null)
                          Chip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  appState.selectedFavorite! ? Icons.favorite : Icons.favorite_border,
                                  size: 16,
                                  color: appState.selectedFavorite! ? Colors.red : Colors.grey,
                                ),
                                Text(appState.selectedFavorite! ? 'Fav' : 'Not Fav'),
                              ],
                            ),
                            onDeleted: () => appState.clearSelectedFavorite(),
                          ),
                        // 过滤按钮 - 只在clips tab显示
                        if (_tabController.index == 0)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.filter_list),
                            onSelected: (value) {
                              switch (value) {
                                case 'tags':
                                  _showTagFilterDialog();
                                  break;
                                case 'rating':
                                  _showRatingFilterDialog();
                                  break;
                                case 'favorite':
                                  _showFavoriteFilterDialog();
                                  break;
                                case 'clear_all':
                                  appState.clearAllFilters();
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem<String>(
                                value: 'tags',
                                child: Row(
                                  children: [
                                    Icon(Icons.label),
                                    SizedBox(width: 8),
                                    Text('Filter by Tags'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem<String>(
                                value: 'rating',
                                child: Row(
                                  children: [
                                    Icon(Icons.star),
                                    SizedBox(width: 8),
                                    Text('Filter by Rating'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem<String>(
                                value: 'favorite',
                                child: Row(
                                  children: [
                                    Icon(Icons.favorite),
                                    SizedBox(width: 8),
                                    Text('Filter by Favorite'),
                                  ],
                                ),
                              ),
                              if (appState.selectedTags.isNotEmpty || 
                                  appState.selectedRating != null || 
                                  appState.selectedFavorite != null)
                                const PopupMenuDivider(),
                              if (appState.selectedTags.isNotEmpty || 
                                  appState.selectedRating != null || 
                                  appState.selectedFavorite != null)
                                const PopupMenuItem<String>(
                                  value: 'clear_all',
                                  child: Row(
                                    children: [
                                      Icon(Icons.clear_all),
                                      SizedBox(width: 8),
                                      Text('Clear All Filters'),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        if (_searchQuery.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _searchController.clear(),
                          ),
                      ],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    ClipsTab(
                      searchQuery: _searchQuery,
                      selectedTags: appState.selectedTags,
                      selectedRating: appState.selectedRating,
                      selectedFavorite: appState.selectedFavorite,
                    ),
                    VideosTab(
                      searchQuery: _searchQuery,
                      selectedTags: appState.selectedTags,
                      selectedRating: appState.selectedRating,
                      selectedFavorite: appState.selectedFavorite,
                    ),
                    PlaylistsTab(searchQuery: _searchQuery),
                  ],
                ),
              ),
            ],
          ),
          if (appState.isLoading ||
              appState.isSaving ||
              appState.isGeneratingThumbnails)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      appState.isSaving
                          ? 'Saving...'
                          : (appState.isGeneratingThumbnails
                                ? 'Generating Thumbnails...'
                                : 'Loading...'),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
