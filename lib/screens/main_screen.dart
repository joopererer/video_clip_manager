import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
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
  List<String> _selectedTags = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        List<String> tempSelectedTags = List.from(_selectedTags);
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
                            title: Text(tag),
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
                    setState(() => _selectedTags = tempSelectedTags);
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
                        if (_selectedTags.isNotEmpty)
                          Chip(
                            label: Text('${_selectedTags.length}'),
                            onDeleted: () =>
                                setState(() => _selectedTags.clear()),
                          ),
                        IconButton(
                          icon: const Icon(Icons.filter_list),
                          onPressed: _showTagFilterDialog,
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
                      selectedTags: _selectedTags,
                    ),
                    VideosTab(searchQuery: _searchQuery),
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
