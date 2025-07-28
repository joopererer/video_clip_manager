import 'package:flutter/material.dart';

class PlaylistsTab extends StatelessWidget {
  final String searchQuery;
  const PlaylistsTab({super.key, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    // This is a placeholder for the playlist functionality
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.playlist_play, size: 80, color: Colors.grey),
          SizedBox(height: 20),
          Text(
            'Playlist Feature Coming Soon!',
            style: TextStyle(fontSize: 22, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
