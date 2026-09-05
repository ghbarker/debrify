import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import '../../models/debrify_tv/channel.dart';
import '../../models/debrify_tv_cache.dart';
import '../debrify_tv_zip_importer.dart';

/// Origin `_ChannelImportOrigin`.
enum ChannelImportOrigin { device, url }

/// Origin `_ChannelImportType`.
enum ChannelImportType { zip, yaml, text, debrify }

/// Origin `_formatBytes`.
String formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  final exponent = min(units.length - 1, (log(bytes) / log(1024)).floor());
  final value = bytes / pow(1024, exponent);
  final formatted = value >= 10
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$formatted ${units[exponent]}';
}

/// Origin `_formatImportError`.
String formatImportError(Object error) {
  if (error is FormatException) {
    return error.message;
  }
  return error.toString().replaceFirst('Exception: ', '').trim();
}

/// Origin `_stripExtension`.
String stripExtension(String name) {
  final dotIndex = name.lastIndexOf('.');
  if (dotIndex <= 0) {
    return name.trim();
  }
  return name.substring(0, dotIndex).trim();
}

/// Origin `_guessExtensionFromHeaders`.
String guessExtensionFromHeaders(Map<String, String> headers) {
  final contentType =
      headers['content-type'] ?? headers['Content-Type'] ?? 'text/plain';
  if (contentType.contains('zip')) {
    return 'zip';
  }
  if (contentType.contains('yaml') || contentType.contains('yml')) {
    return 'yaml';
  }
  return 'txt';
}

/// Origin `_determineImportType`.
ChannelImportType? determineImportType(String sourceName, Uint8List bytes) {
  final lower = sourceName.toLowerCase();

  // Check extension first
  if (lower.endsWith('.zip')) {
    return ChannelImportType.zip;
  }
  if (lower.endsWith('.debrify')) {
    return ChannelImportType.debrify;
  }
  if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
    return ChannelImportType.yaml;
  }
  if (lower.endsWith('.txt')) {
    return ChannelImportType.text;
  }

  // Fallback: check file signature for zip
  if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
    // PK — zip signature
    return ChannelImportType.zip;
  }

  // Smart content detection for unknown extensions
  try {
    final content = utf8.decode(bytes).trim();
    if (content.startsWith('debrify://')) {
      return ChannelImportType.debrify;
    }
  } catch (_) {
    // If UTF-8 decode fails, not a text file
  }

  return null;
}

/// Origin `_resolveUniqueChannelName`.
String resolveUniqueChannelName(
  String baseName,
  Set<String> usedLowerCaseNames,
) {
  final String trimmed = baseName.trim().isEmpty
      ? 'Imported Channel'
      : baseName.trim();
  String candidate = trimmed;
  int suffix = 2;
  while (usedLowerCaseNames.contains(candidate.toLowerCase())) {
    candidate = '$trimmed ($suffix)';
    suffix++;
  }
  return candidate;
}

/// Origin `_escapeYamlString`.
String escapeYamlString(String value) {
  // Escape special characters for YAML string
  return value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');
}

Future<DebrifyTvZipImportResult> parseZipInBackground(Uint8List bytes) {
  return compute(parseZipCompute, bytes);
}

DebrifyTvZipImportResult parseZipCompute(Uint8List bytes) {
  return DebrifyTvZipImporter.parseZip(bytes);
}

Future<DebrifyTvZipImportedChannel> parseYamlInBackground(
  String sourceName,
  String content,
) {
  return compute(parseYamlCompute, <String, String>{
    'sourceName': sourceName,
    'content': content,
  });
}

DebrifyTvZipImportedChannel parseYamlCompute(Map<String, String> payload) {
  final sourceName = payload['sourceName'] ?? 'channel.yaml';
  final content = payload['content'] ?? '';
  return DebrifyTvZipImporter.parseYaml(
    sourceName: sourceName,
    content: content,
  );
}

/// Text-file keyword parsing from the M1-2 import flow; limits are unchanged.
List<String> parseChannelText(Uint8List bytes) {
  final content = utf8.decode(bytes);
  final keywords = <String>[];
  final seen = <String>{};

  final lines = const LineSplitter().convert(content);
  for (final rawLine in lines) {
    final parts = rawLine.split(',');
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (trimmed.length > 120) {
        throw FormatException(
          'Keyword exceeds 120 characters: "${trimmed.substring(0, trimmed.length > 40 ? 40 : trimmed.length)}${trimmed.length > 40 ? '…' : ''}"',
        );
      }
      final lower = trimmed.toLowerCase();
      if (seen.add(lower)) {
        keywords.add(trimmed);
      }
    }
  }

  if (keywords.isEmpty) {
    throw const FormatException('No keywords found in the selected file.');
  }
  if (keywords.length > 500) {
    throw const FormatException(
      'Channel files must contain 500 keywords or fewer.',
    );
  }

  return keywords;
}

/// YAML serialization from M1-2; the screen flow supplies persisted torrents.
String serializeChannelYaml(
  DebrifyTvChannel channel,
  List<CachedTorrent> cachedTorrents,
) {
  // Generate YAML with channel config and torrent data from cache
  final buffer = StringBuffer();
  buffer.writeln('channel_name: "${channel.name}"');
  buffer.writeln('avoid_nsfw: ${channel.avoidNsfw}');
  buffer.writeln('');
  buffer.writeln('keywords:');

  for (final keyword in channel.keywords) {
    buffer.writeln('  $keyword:');

    // Find all torrents that match this keyword (case-insensitive)
    final keywordLower = keyword.toLowerCase();
    final matchingTorrents = cachedTorrents
        .where((t) => t.keywords.contains(keywordLower))
        .toList();

    // Dedupe by infohash
    final seen = <String>{};
    final uniqueTorrents = matchingTorrents.where((t) {
      if (seen.contains(t.infohash)) return false;
      seen.add(t.infohash);
      return true;
    }).toList();

    if (uniqueTorrents.isEmpty) {
      buffer.writeln('    torrents: []');
    } else {
      buffer.writeln('    torrents:');
      for (final torrent in uniqueTorrents) {
        // Output full torrent object for proper import
        buffer.writeln('      - infohash: ${torrent.infohash}');
        buffer.writeln('        name: "${escapeYamlString(torrent.name)}"');
        buffer.writeln('        size_bytes: ${torrent.sizeBytes}');
        buffer.writeln('        created_unix: ${torrent.createdUnix}');
        buffer.writeln('        seeders: ${torrent.seeders}');
        buffer.writeln('        leechers: ${torrent.leechers}');
        buffer.writeln('        completed: ${torrent.completed}');
        buffer.writeln('        scraped_date: ${torrent.scrapedDate}');
        if (torrent.sources.isNotEmpty) {
          buffer.writeln(
            '        sources: [${torrent.sources.map((s) => '"$s"').join(', ')}]',
          );
        }
      }
    }
  }

  return buffer.toString();
}
