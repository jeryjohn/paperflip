import 'package:flutter/widgets.dart';

/// Signature for a function that builds a single page widget.
///
/// [index] is the zero-based page index.
/// [constraints] are the [BoxConstraints] for the page area — useful for
/// sizing content relative to the available space.
typedef FlipPageBuilder =
    Widget Function(
      BuildContext context,
      int index,
      BoxConstraints constraints,
    );
