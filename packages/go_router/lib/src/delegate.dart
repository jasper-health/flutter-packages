// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'builder.dart';
import 'configuration.dart';
import 'match.dart';
import 'matching.dart';
import 'typedefs.dart';

/// GoRouter implementation of [RouterDelegate].
class GoRouterDelegate extends RouterDelegate<RouteMatchList>
    with PopNavigatorRouterDelegateMixin<RouteMatchList>, ChangeNotifier {
  /// Constructor for GoRouter's implementation of the RouterDelegate base
  /// class.
  GoRouterDelegate({
    required RouteConfiguration configuration,
    required GoRouterBuilderWithNav builderWithNav,
    required GoRouterPageBuilder? errorPageBuilder,
    required GoRouterWidgetBuilder? errorBuilder,
    required List<NavigatorObserver> observers,
    required this.routerNeglect,
    String? restorationScopeId,
  }) : builder = RouteBuilder(
          configuration: configuration,
          builderWithNav: builderWithNav,
          errorPageBuilder: errorPageBuilder,
          errorBuilder: errorBuilder,
          restorationScopeId: restorationScopeId,
          observers: observers,
        );

  /// Builds the top-level Navigator given a configuration and location.
  @visibleForTesting
  final RouteBuilder builder;

  /// Set to true to disable creating history entries on the web.
  final bool routerNeglect;

  final GlobalKey<NavigatorState> _key = GlobalKey<NavigatorState>();

  RouteMatchList _matches = RouteMatchList.empty();
  final Map<String, int> _pushCounts = <String, int>{};

  final Map<String, Completer<dynamic>> _completerList = <String, Completer<dynamic>>{};

  ///Used in pair with [setPageResult] to create unique path for bind together with [awaitForResult]
  String get pagesRoute => _getPagesRoute(currentConfiguration);

  ///Used in pair with [setPageResult] to create unique path for bind together with [awaitForResult]
  String _getPagesRoute(RouteMatchList matchList) {
    //Taking all stack element Uris to have unique path which target to current page
    return matchList.matches
        .fold<String>('', (String previousValue, RouteMatch element) => previousValue + element.fullUriString);
  }

  /// Provide option to await for page close
  /// Should removed later after all code refactored
  ///
  /// RECOMMENDATION: Designed to use directly next after route was pushed/go/etc. to take/subscribe to new route path
  /// Later when pop with this route will be executed we receive completed future
  Future<dynamic> awaitForResult({String? route}) async {
    final String routeName = route ?? pagesRoute;
    final Completer<dynamic>? completer = _completerList[routeName];
    if (completer != null && !completer.isCompleted) {
      return completer.future;
    }
    _completerList[routeName] = Completer<dynamic>();
    return _completerList[routeName]?.future;
  }

  /// Used to send some result as page result during page closing
  void setPageResult({
    String? route,
    dynamic result,
  }) {
    final String routeName = route ?? pagesRoute;
    log('GoRouterDelegate setPageResult');
    _completerList.removeWhere((String key, Completer<dynamic> value) {
      if (key == routeName) {
        log('GoRouterDelegate setPageResult: pagesRoute = $routeName');
        value.complete(result);
        return true;
      }
      return false;
    });
  }

  /// Pop top routes from until meet provided path pattern
  void popUntil({required String? fullUriString}) {
    while ((fullUriString != _matches.last.fullUriString) && _matches.canPop()) {
      //Setting result to last pagesRoute and then pop last route out from stack
      setPageResult(route: pagesRoute);
      _matches.pop();
    }
    notifyListeners();
  }

  /// Pushes the given location onto the page stack
  void push(RouteMatch match) {
    // Remap the pageKey to allow any number of the same page on the stack
    final String fullPath = match.fullpath;
    final int count = (_pushCounts[fullPath] ?? 0) + 1;
    _pushCounts[fullPath] = count;
    final ValueKey<String> pageKey = ValueKey<String>('$fullPath-p$count');
    final RouteMatch newPageKeyMatch = RouteMatch(
      route: match.route,
      subloc: match.subloc,
      fullpath: match.fullpath,
      encodedParams: match.encodedParams,
      queryParams: match.queryParams,
      extra: match.extra,
      error: match.error,
      pageKey: pageKey,
    );

    _matches.push(newPageKeyMatch);
    notifyListeners();
  }

  /// Returns `true` if there is more than 1 page on the stack.
  bool canPop() {
    return _matches.canPop();
  }

  /// Pop the top page off the GoRouter's page stack.
  void pop({dynamic result}) {
    //Setting result to last pagesRoute and then pop last route out from stack
    setPageResult(route: pagesRoute, result: result);
    _matches.pop();
    notifyListeners();
  }

  /// Replaces the top-most page of the page stack with the given one.
  ///
  /// See also:
  /// * [push] which pushes the given location onto the page stack.
  void replace(RouteMatch match) {
    //Setting result to last pagesRoute and then pop last route out from stack
    setPageResult(route: pagesRoute);
    _matches.matches.last = match;
    notifyListeners();
  }

  /// For internal use; visible for testing only.
  @visibleForTesting
  RouteMatchList get matches => _matches;

  /// For use by the Router architecture as part of the RouterDelegate.
  @override
  GlobalKey<NavigatorState> get navigatorKey => _key;

  /// For use by the Router architecture as part of the RouterDelegate.
  @override
  RouteMatchList get currentConfiguration => _matches;

  /// For use by the Router architecture as part of the RouterDelegate.
  @override
  Widget build(BuildContext context) => builder.build(
        context,
        _matches,
        pop,
        navigatorKey,
        routerNeglect,
      );

  /// For use by the Router architecture as part of the RouterDelegate.
  @override
  Future<void> setNewRoutePath(RouteMatchList configuration) {
    _matches.location.pathSegments.fold<String>('', (String previousValue, String element) {
      final String result = previousValue + element;
      setPageResult(route: result);
      return result;
    });
    _matches = configuration;
    // Use [SynchronousFuture] so that the initial url is processed
    // synchronously and remove unwanted initial animations on deep-linking
    return SynchronousFuture<void>(null);
  }

  @override
  void dispose() {
    _completerList.forEach((String key, Completer<dynamic> value) {
      value.complete();
    });
    super.dispose();
  }
}
