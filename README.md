# <img src='Workflow/icon.png' width='45' align='center' alt='icon'> Watch List Alfred Workflow

Play and manage local media and streams

<a href='https://alfred.app/workflows/vitor/watch-list'>⤓ Install From the Alfred Gallery</a>

## Usage

Add files, series (folders), and streams (URLs) to your watchlist via the [Universal Action](https://www.alfredapp.com/help/features/universal-actions/).

![Universal action for adding to watchlist](Workflow/images/about/ua.png)

Search through and play items from your list via the Play Keyword (default: `wlp`).

![Showing items to play](Workflow/images/about/wlp.png)

* <kbd>⏎</kbd>: Play.
* <kbd>⌃</kbd><kbd>⏎</kbd> Open the item’s URL in a web browser.
* <kbd>⌥</kbd><kbd>⏎</kbd>:
    * series: Rescan folder for audiovisual files.
    * stream: Download. Requires [Download Media](https://alfred.app/workflows/vitor/download-media/).
* <kbd>⌘</kbd><kbd>⏎</kbd>: Mark as watched without playing.
* <kbd>⇧</kbd><kbd>⏎</kbd>: Add to temporary playlist. Repeat for all desired items then <kbd>⏎</kbd> to play them in order. An unplayed playlist is reset after a few minutes.
* <kbd>⌘</kbd><kbd>Y</kbd> (or tap <kbd>⇧</kbd>): Quick Look files and streams.

Try the Sort and Play Keyword (default: `wls`) to get different views of your list. Sorting is temporary and does not affect the main list’s order.

![Showing sort options](Workflow/images/about/wls.png)

Manually edit the list via the Edit Keyword (default: `wle`). Your text editor will open for you to reorder and rename at will. Keep the initial six characters and colon together with your title. Save and quit your editor to apply the changes.

![Edit list](Workflow/images/about/wle.png)

Undo marking an item as watched via the Unwatch Keyword (default: `wlu`). <kbd>⏎</kbd> to mark not watched and try to recover from the trash.

![Showing watched items](Workflow/images/about/wlu.png)

If the item has an origin URL (shown in the subtitle):

* <kbd>⌘</kbd><kbd>⏎</kbd>: Open URL in a web browser.
* <kbd>⌥</kbd><kbd>⏎</kbd>: Copy to the clipboard.
* <kbd>⌘</kbd><kbd>Y</kbd> (or tap <kbd>⇧</kbd>): Quick Look.

### Subtitle reference:

There are three types of item: file, series, and stream. Each result has its name as the title. The subtitle details information following a template:

```
≈ (4) 𐄁 22m 32s 𐄁 691M 𐄁 /Some/Path
```

* `≈`: Indicates item is a stream.
    * file: N/A.
    * series: N/A.
    * stream: Always present.
* `(4)`: Number of elements.
    * file: N/A.
    * series: Remaining audiovisual files in folder.
    * stream: N/A for single items. Count of all items for playlists.
* `22m 32s`: Running time.
    * file: Running time of file.
    * series: Running time of first audiovisual file in folder.
    * stream: Combined running time of all elements.
* `691M`: Size.
    * file: Size of file.
    * series: Size of first audiovisual file in folder.
    * stream: N/A.
* `/Some/Path`: Path.
    * file: Path to file.
    * series: Path to folder.
    * stream: URL.

## Supported Players

All media players are supported, but not all are able to play streams. [mpv](http://mpv.io/), [IINA](https://lhc70000.github.io/iina/), and [VLC](http://www.videolan.org/vlc/index.html) are directly supported. With those, an item is not marked as watched if playback exits with a non-zero code. Take advantage of that to, for example, control when an item is marked as item and trashed. Disable the trashing behaviour entirely in the [Workflow’s Configuration](https://www.alfredapp.com/help/workflows/user-configuration/).
