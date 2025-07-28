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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Clip Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Load Clips from JSON',
            onPressed: appState.isLoading
                ? null
                : () async {
                    final result = await appState.loadClipsFromFile();
                    _showSnackBar(result);
                  },
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save Clips to JSON',
            onPressed: appState.isLoading
                ? null
                : () async {
                    final result = await appState.saveClipsToFile();
                    _showSnackBar(result);
                  },
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    ClipsTab(searchQuery: _searchQuery),
                    VideosTab(searchQuery: _searchQuery),
                    PlaylistsTab(searchQuery: _searchQuery),
                  ],
                ),
              ),
            ],
          ),
          if (appState.isLoading)
            const Opacity(
              opacity: 0.8,
              child: ModalBarrier(dismissible: false, color: Colors.black),
            ),
          if (appState.isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
