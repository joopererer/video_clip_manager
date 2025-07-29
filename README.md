# Video Clip Manager

A Flutter application for managing video clips with advanced editing capabilities.

## Features

### Core Features
- Load and manage video clips from JSON files
- Create and edit video clips with precise time controls
- Generate thumbnails for clips
- Tag-based organization system
- Playlist management
- Search and filter functionality

### Enhanced Clips Tab Interface
The clips tab now features an optimized interface with two display modes:

#### List View
- **Star Rating System**: Click on stars to rate clips (1-5 stars, click again to remove rating)
- **Favorite System**: Heart icon to mark/unmark clips as favorites
- **Enhanced Information Display**: Shows start time, end time, duration, and tags
- **Direct Editing**: Click edit button to open clip editor
- **Quick Actions**: Play, edit, and delete buttons for each clip

#### Grid View
- **Compact Card Layout**: Visual cards with thumbnails
- **Interactive Controls**: 
  - Star rating system with clickable stars
  - Favorite toggle with heart icon
  - Play button for quick preview
  - Edit and delete buttons in header
- **Visual Indicators**: Favorite clips show heart icon in header
- **Duration Display**: Shows clip duration in monospace font
- **Responsive Design**: Adjusts grid size based on screen width

### Key Improvements
1. **Direct Interaction**: Click on stars or heart icons to modify ratings and favorites directly from the clips list
2. **Visual Feedback**: Clear visual indicators for ratings and favorites
3. **Consistent Design**: Both list and grid views maintain consistent functionality
4. **Performance**: Optimized rendering with proper state management
5. **User Experience**: Intuitive controls that don't require opening the editor for simple changes

## Usage

### Rating Clips
- Click on the star icons in either view mode to set a rating (1-5 stars)
- Click the same star again to remove the rating
- Ratings are automatically saved

### Favoriting Clips
- Click the heart icon to toggle favorite status
- Favorite clips show a red heart icon
- Favorites are automatically saved

### Switching View Modes
- Use the view mode toggle button in the top-right corner of the clips tab
- Choose between list view (detailed) and grid view (visual)

## Technical Details

The enhanced clips tab implementation includes:
- State management through Provider pattern
- Real-time updates using `context.watch<AppState>()`
- Optimized UI components with proper gesture detection
- Consistent styling across both view modes
- Integration with existing clip editor functionality

## Development

This project uses:
- Flutter 3.32.8
- Provider for state management
- Media Kit for video playback
- Shared Preferences for settings persistence
