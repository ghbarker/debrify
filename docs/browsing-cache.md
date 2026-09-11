# Faster browsing

Open **Settings → Data & Backup → Faster browsing**. These storage choices belong to this device, so a phone's limits do not replace a TV's limits during a profile transfer or sync.

## Saved title lists

Enable **Remember title lists** to save add-on catalog pages between app launches. Choose 10, 25, 50, or 100 MB. Pages include names, basic card metadata, and artwork addresses. Image files use the separate artwork cache.

A saved page can appear before its network request finishes. The background request prepares an updated page for the next visit; it does not replace a focused row while you are navigating. Saved pages expire after 24 hours. Explicit refresh requests bypass saved pages. Failed requests are retried on the next visit.

Saved pages are isolated by profile, profile data generation, add-on configuration, and metadata preferences. The selected storage allowance covers all profiles on this device. Native TMDB and Trakt catalogs retain their existing caching behavior.

## Artwork storage

Enable **Custom artwork cache** and choose 128 MB, 256 MB, 512 MB, 1 GB, or 2 GB. This allowance covers Debrify's shared artwork store and IPTV channel logos, including resized copies. Other app data, downloaded videos, and images using another cache manager are separate.

Artwork is retained as it is requested during browsing. Older unused files make room for new artwork. Files currently being read can remain temporarily after a reduction or clear; they still count against admission of new files. Changing this option does not increase Flutter's decoded-image memory allowance.

With the option off, the shared stores use their standard item-count limits. The operating system may clear disposable cached files when it needs space.

The **Cached storage** rows show measured file sizes and let you clear the saved lists or shared artwork. Opening this Settings page performs the measurement; Home startup does not wait for it.

## Prepare movie streams

With **Prepare movie streams** on, opening a movie's detail page starts add-on source discovery. Pressing Play can join the request already running or reuse a recent result. Source selection and playback still follow the existing flow.

Preparation only requests source listings. Playback, watch-history updates, media downloads, and debrid transfer creation start through the normal Play flow. Results live briefly in memory and are invalidated when the relevant profile or add-on configuration changes.

Source discovery is only one part of starting a movie. Provider authorization, resolving a playable address, player startup, and buffering can still take time.

## Optional TMDB setup

You can add your own **TMDB API Read Access Token** on the existing metadata Settings page. The editor masks new input and does not display the saved token. Saving a replacement takes effect without rebuilding the app. Saving an empty value removes your override and falls back to a token bundled in the build, if one exists.

The runtime token belongs to its profile and uses the existing connection credential vault. Add-on browsing works without a TMDB token. Native TMDB catalogs and TMDB-selected metadata need one.
