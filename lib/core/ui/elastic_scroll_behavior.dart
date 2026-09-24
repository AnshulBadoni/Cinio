import 'package:flutter/material.dart';

/// App-wide scroll behavior: use native-feeling elastic overscroll instead of
/// Android's glow. Keeping this at the app level means newly added pages get
/// the same interaction without every ListView/GridView needing custom code.
class CinioScrollBehavior extends MaterialScrollBehavior {
  const CinioScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }
}


class CinioBounceOnlyScrollBehavior extends MaterialScrollBehavior {
  const CinioBounceOnlyScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}
