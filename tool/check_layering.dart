// Import-layering check for plan §3. Default is warn-only (exit 0) so Phase 0
// can land while models still import Flutter. Pass --strict to fail (lane Q1).
//
// models:     no Flutter, no services
// services:   no Flutter widgets, no lib/widgets
// widgets:    never screens
// screens:    never another screen's private parts

import 'dart:io';

enum Layer { models, services, widgets, screens, other }

class Violation {
  Violation(this.file, this.importSpec, this.rule, this.detail);

  final String file;
  final String importSpec;
  final String rule;
  final String detail;

  @override
  String toString() => '$file: import "$importSpec" — $rule ($detail)';
}

final _importRe = RegExp(r'''^\s*import\s+(?:deferred\s+)?['"]([^'"]+)['"]''');

Layer layerFor(String relPosix) {
  if (relPosix.startsWith('lib/models/')) return Layer.models;
  if (relPosix.startsWith('lib/services/')) return Layer.services;
  if (relPosix.startsWith('lib/widgets/')) return Layer.widgets;
  if (relPosix.startsWith('lib/screens/')) return Layer.screens;
  return Layer.other;
}

String posix(String path) => path.replaceAll(r'\', '/');

String relativeToRoot(String path, String root) {
  final n = posix(path);
  final r = posix(root);
  if (n == r) return '';
  final prefix = r.endsWith('/') ? r : '$r/';
  if (n.startsWith(prefix)) return n.substring(prefix.length);
  return n;
}

String normalizePosix(String path) {
  final parts = <String>[];
  final absolute = path.startsWith('/');
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(part);
  }
  final out = parts.join('/');
  if (absolute) return '/$out';
  return out;
}

String? resolveImport(String fromRel, String spec) {
  if (spec.startsWith('package:debrify/')) {
    return 'lib/${spec.substring('package:debrify/'.length)}';
  }
  if (spec.startsWith('package:') || spec.startsWith('dart:')) {
    return spec;
  }
  final fromDir = fromRel.contains('/')
      ? fromRel.substring(0, fromRel.lastIndexOf('/'))
      : '';
  final joined = fromDir.isEmpty ? spec : '$fromDir/$spec';
  return normalizePosix(joined);
}

bool isFlutterPackage(String spec) => spec.startsWith('package:flutter/');

bool isFlutterWidgetsImport(String spec) {
  if (spec == 'package:flutter/material.dart' ||
      spec == 'package:flutter/cupertino.dart' ||
      spec == 'package:flutter/widgets.dart') {
    return true;
  }
  if (spec.startsWith('package:flutter/') && spec.contains('widgets')) {
    return true;
  }
  return false;
}

bool isServicesImport(String spec, String? resolved) {
  if (spec.startsWith('package:debrify/services/')) return true;
  if (resolved != null && posix(resolved).startsWith('lib/services/')) {
    return true;
  }
  return false;
}

bool isWidgetsLibImport(String spec, String? resolved) {
  if (spec.startsWith('package:debrify/widgets/')) return true;
  if (resolved != null && posix(resolved).startsWith('lib/widgets/')) {
    return true;
  }
  return false;
}

bool isScreensImport(String spec, String? resolved) {
  if (spec.startsWith('package:debrify/screens/')) return true;
  if (resolved != null && posix(resolved).startsWith('lib/screens/')) {
    return true;
  }
  return false;
}

/// `lib/screens/foo_screen.dart` → foo_screen.dart
/// `lib/screens/search/x.dart` → search
String? screenRoot(String rel) {
  const prefix = 'lib/screens/';
  if (!rel.startsWith(prefix)) return null;
  final rest = rel.substring(prefix.length);
  final slash = rest.indexOf('/');
  if (slash < 0) return rest;
  return rest.substring(0, slash);
}

bool looksPrivateScreenTarget(String rel, String root) {
  final name = rel.split('/').last;
  if (name.startsWith('_')) return true;
  final file = File('$root/$rel');
  if (!file.existsSync()) return false;
  final head = file.readAsStringSync();
  final probe = head.length > 4000 ? head.substring(0, 4000) : head;
  return RegExp(r'^part of ', multiLine: true).hasMatch(probe);
}

List<String> collectDartFiles(String dir) {
  final out = <String>[];
  final folder = Directory(dir);
  if (!folder.existsSync()) return out;
  for (final entity in folder.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final p = posix(entity.path);
    if (!p.endsWith('.dart')) continue;
    if (p.endsWith('.g.dart') || p.endsWith('.freezed.dart')) continue;
    out.add(p);
  }
  out.sort();
  return out;
}

List<Violation> checkRepo({String? root}) {
  final rootPath = posix(root ?? Directory.current.path);
  final lib = '$rootPath/lib';
  final violations = <Violation>[];
  for (final abs in collectDartFiles(lib)) {
    final rel = relativeToRoot(abs, rootPath);
    final layer = layerFor(rel);
    if (layer == Layer.other) continue;
    final text = File(abs).readAsStringSync();
    for (final line in text.split('\n')) {
      final match = _importRe.firstMatch(line);
      if (match == null) continue;
      final spec = match.group(1)!;
      final resolved = resolveImport(rel, spec);
      switch (layer) {
        case Layer.models:
          if (isFlutterPackage(spec) || spec.startsWith('dart:ui')) {
            violations.add(
              Violation(rel, spec, 'models: no Flutter', 'pure data layer'),
            );
          }
          if (isServicesImport(spec, resolved)) {
            violations.add(
              Violation(rel, spec, 'models: no services', 'pure data layer'),
            );
          }
          if (isScreensImport(spec, resolved) ||
              isWidgetsLibImport(spec, resolved)) {
            violations.add(
              Violation(rel, spec, 'models: no UI', 'pure data layer'),
            );
          }
          break;
        case Layer.services:
          if (isFlutterWidgetsImport(spec)) {
            violations.add(
              Violation(
                rel,
                spec,
                'services: no Flutter widgets',
                'logic layer',
              ),
            );
          }
          if (isWidgetsLibImport(spec, resolved)) {
            violations.add(
              Violation(rel, spec, 'services: no widgets', 'logic layer'),
            );
          }
          if (isScreensImport(spec, resolved)) {
            violations.add(
              Violation(rel, spec, 'services: no screens', 'logic layer'),
            );
          }
          break;
        case Layer.widgets:
          if (isScreensImport(spec, resolved)) {
            violations.add(
              Violation(
                rel,
                spec,
                'widgets: never screens',
                'extract shared UI, do not import screens',
              ),
            );
          }
          break;
        case Layer.screens:
          if (resolved != null && posix(resolved).startsWith('lib/screens/')) {
            final fromRoot = screenRoot(rel);
            final toRoot = screenRoot(posix(resolved));
            if (fromRoot != null &&
                toRoot != null &&
                fromRoot != toRoot &&
                looksPrivateScreenTarget(posix(resolved), rootPath)) {
              violations.add(
                Violation(
                  rel,
                  spec,
                  "screens: never another screen's private parts",
                  '$fromRoot → $toRoot',
                ),
              );
            }
          }
          break;
        case Layer.other:
          break;
      }
    }
  }
  return violations;
}

void report(List<Violation> violations, {required bool strict}) {
  stdout.writeln(
    'Import layering (plan §3): ${violations.length} violation(s). '
    '${strict ? 'strict' : 'warn-only (Q1 turns this into failure)'}.',
  );
  final byRule = <String, int>{};
  for (final v in violations) {
    byRule[v.rule] = (byRule[v.rule] ?? 0) + 1;
  }
  final rules = byRule.keys.toList()..sort();
  for (final rule in rules) {
    stdout.writeln('  ${byRule[rule]}  $rule');
  }
  const cap = 40;
  for (final v in violations.take(cap)) {
    stdout.writeln('  $v');
  }
  if (violations.length > cap) {
    stdout.writeln('  … ${violations.length - cap} more');
  }
}

void main(List<String> args) {
  final strict = args.contains('--strict');
  final violations = checkRepo();
  report(violations, strict: strict);
  if (strict && violations.isNotEmpty) {
    exit(1);
  }
}
