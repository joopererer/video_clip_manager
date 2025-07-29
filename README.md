# Video Clip Manager

A Flutter application for managing video clips with advanced editing capabilities.

## Features

### Core Features
- Load and manage video clips from JSON files
- Create and edit video clips with precise time controls
- Generate thumbnails for clips
- Tag-based organization system with automatic colorization
- Playlist management
- Advanced search and filter functionality
  - Text search across clip names, notes, and file paths
  - Tag-based filtering with multi-tag support
  - Star rating filtering (1-5 stars)
  - Favorite status filtering (favorites only, not favorites, or all)

### Enhanced Clips Tab Interface
The clips tab now features an optimized interface with two display modes:

### Enhanced Clip Playback Screen
The clip playback screen has been completely redesigned with advanced features:

#### Playback Controls
- **Replay Button**: Instantly restart the clip from the beginning
- **Play/Pause Toggle**: Control playback with overlay controls on the video
- **Automatic Loop**: Clips automatically stop at the end time and can be replayed

#### Interactive Features
- **Star Rating System**: Click on stars to rate clips directly from the player
- **Favorite Toggle**: Heart icon to mark/unmark clips as favorites
- **Direct Editing**: Edit button to open the clip editor for modifications

#### Navigation
- **Previous/Next Buttons**: Navigate between clips in the collection
- **Seamless Transitions**: Switch between clips without closing the player
- **Visual Feedback**: Disabled buttons when no previous/next clips available

#### Information Display
- **Time Range**: Shows start time, end time, and total duration
- **Tags and Notes**: Displays clip metadata when available, with colored tag chips
- **Video File**: Shows the source video filename
- **Enhanced Layout**: Larger window (720x680) for better viewing experience

#### Technical Features
- **State Management**: Real-time updates for ratings and favorites
- **Responsive Design**: Adapts to different screen sizes
- **Memory Efficient**: Proper cleanup of video resources
- **Error Handling**: Graceful handling of missing files or navigation errors

#### Sorting and Statistics
- **Advanced Sorting**: 8 different sorting options including:
  - Name (A-Z / Z-A)
  - Date Added (Newest / Oldest)
  - Rating (High to Low / Low to High)
  - Duration (Long to Short / Short to Long)
- **Real-time Statistics**: Shows filtered count vs total count (e.g., "15 / 25")
- **Smart Default**: Sorts by newest clips first by default
- **Instant Sorting**: Results update immediately when sorting option changes
- **Beautiful UI**: Modern design with gradients, shadows, and smooth animations

#### List View
- **Star Rating System**: Click on stars to rate clips (1-5 stars, click again to remove rating)
- **Favorite System**: Heart icon to mark/unmark clips as favorites
- **Enhanced Information Display**: Shows start time, end time, duration, and tags
- **Tag Colorization**: Each tag displays with a unique, consistent color based on its content
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
2. **Advanced Sorting**: Comprehensive sorting options for better organization
3. **Real-time Statistics**: Always know how many clips are being displayed vs total
4. **Visual Feedback**: Clear visual indicators for ratings and favorites
5. **Consistent Design**: Both list and grid views maintain consistent functionality
6. **Performance**: Optimized rendering with proper state management
7. **User Experience**: Intuitive controls that don't require opening the editor for simple changes

## Usage

### Sorting Clips
- Use the beautiful sorting dropdown menu in the top-left of the clips tab
- Choose from 8 different sorting options
- Results update immediately when you change the sort order
- Default sorting is by newest clips first
- Modern UI with smooth animations and visual feedback

### Rating Clips
- Click on the star icons in either view mode to set a rating (1-5 stars)
- Click the same star again to remove the rating
- Ratings are automatically saved

### Favoriting Clips
- Click the heart icon to toggle favorite status
- Favorite clips show a red heart icon
- Favorites are automatically saved

### Viewing Statistics
- The blue badge shows "filtered count / total count"
- Updates automatically when you search, filter, or sort
- Helps you understand how many clips match your current criteria

### Switching View Modes
- Use the view mode toggle button in the top-right corner of the clips tab
- Choose between list view (detailed) and grid view (visual)

### Using the Enhanced Playback Screen
- **Play Clips**: Click the play button on any clip to open the enhanced playback screen
- **Replay**: Use the replay button to restart the clip from the beginning
- **Rate While Playing**: Click on stars to rate clips directly from the player
- **Toggle Favorites**: Use the heart icon to mark/unmark favorites during playback
- **Navigate Clips**: Use previous/next buttons to browse through your clip collection
- **Edit on the Fly**: Click the edit button to open the clip editor for modifications
- **View Details**: See comprehensive information including time range, tags, and notes

### Advanced Filtering
- **Text Search**: Type in the search bar to filter by clip name, notes, or file path
- **Tag Filtering**: Click the filter button and select "Filter by Tags" to choose multiple tags
            - **Rating Filtering**: Click the filter button and select "Filter by Rating" to filter by specific star ratings (including "No Rating" for clips without stars)
- **Favorite Filtering**: Click the filter button and select "Filter by Favorite" to show only favorites, only non-favorites, or all clips
- **Combined Filters**: Use multiple filter types simultaneously for precise filtering
- **Clear Filters**: Use "Clear All Filters" option or click the X on individual filter chips
- **Visual Indicators**: Active filters are displayed as chips in the search bar with icons and counts

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
