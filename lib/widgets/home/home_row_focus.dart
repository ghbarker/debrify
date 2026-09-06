import 'package:flutter/widgets.dart';

/// Reuses focus nodes by row/content identity across background Home refreshes.
List<List<FocusNode>> reconcileHomeRowFocus({
  required List<List<String>> previousIds,
  required List<List<FocusNode>> previousNodes,
  required List<List<String>> nextIds,
}) {
  final available = <String, List<FocusNode>>{};
  for (var r = 0; r < previousIds.length && r < previousNodes.length; r++) {
    for (
      var c = 0;
      c < previousIds[r].length && c < previousNodes[r].length;
      c++
    ) {
      available
          .putIfAbsent(previousIds[r][c], () => [])
          .add(previousNodes[r][c]);
    }
  }
  final next = [
    for (final row in nextIds)
      [
        for (final id in row)
          switch (available[id]) {
            final List<FocusNode> nodes when nodes.isNotEmpty => nodes.removeAt(
              0,
            ),
            _ => FocusNode(debugLabel: 'home_refreshed_card'),
          },
      ],
  ];
  final removed = previousNodes.expand((row) => row).toSet()
    ..removeAll(next.expand((row) => row));
  for (final node in removed) {
    node.dispose();
  }
  return next;
}
