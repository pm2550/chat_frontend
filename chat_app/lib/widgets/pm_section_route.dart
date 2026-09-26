import 'package:flutter/material.dart';

/// Desktop sections occupy the same workspace. Moving/zooming the entire
/// route also moves its navigation rail, so those routes change in place.
/// Compact layouts retain the platform navigation transition.
class PMSectionRoute<T> extends MaterialPageRoute<T> {
  PMSectionRoute({
    required super.builder,
    super.settings,
    required this.stationary,
  });

  final bool stationary;

  @override
  Duration get transitionDuration =>
      stationary ? Duration.zero : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      stationary ? Duration.zero : super.reverseTransitionDuration;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (stationary) return child;
    return super
        .buildTransitions(context, animation, secondaryAnimation, child);
  }
}
