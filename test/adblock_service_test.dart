import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/browser/adblock_service.dart';
import 'package:cubiclm/views/cubicweb/browser_view.dart';

/// Ad-block matching: pure string logic, no platform channels involved.
/// Guards the privacy promise (blocks trackers) and the false-positive
/// promise (never blanks a page the user chose to open).
void main() {
  final rules = <String>{
    'doubleclick.net',
    'googlesyndication.com',
    'analytics.google.com',
    'facebook.net',
  };

  group('matchesRules', () {
    test('blocks exact host', () {
      expect(AdblockService.matchesRules(
          'https://doubleclick.net/ad?id=1', rules), isTrue);
    });

    test('blocks subdomains of a listed host', () {
      expect(AdblockService.matchesRules(
          'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js',
          rules), isTrue);
      expect(AdblockService.matchesRules(
          'https://connect.facebook.net/en_US/sdk.js', rules), isTrue);
    });

    test('does not block lookalike domains', () {
      // "notdoubleclick.net" merely ends with the same letters — it is
      // NOT a subdomain, so it must pass.
      expect(AdblockService.matchesRules(
          'https://notdoubleclick.net/', rules), isFalse);
      expect(AdblockService.matchesRules(
          'https://doubleclick.net.evil.com/', rules), isFalse);
    });

    test('does not block clean pages', () {
      expect(AdblockService.matchesRules(
          'https://wikipedia.org/wiki/Flutter', rules), isFalse);
      expect(AdblockService.matchesRules(
          'https://arxiv.org/abs/1234.5678', rules), isFalse);
    });

    test('matching is case-insensitive', () {
      expect(AdblockService.matchesRules(
          'https://PageAd2.GoogleSyndication.com/x.js', rules), isTrue);
    });
  });

  group('isBlockedUrl scheme + frame guards', () {
    test('non-http schemes always pass', () {
      expect(AdblockService.isBlockedUrl('about:blank'), isFalse);
      expect(
          AdblockService.isBlockedUrl(
              'data:text/html,<h1>hi</h1>'),
          isFalse);
      expect(AdblockService.isBlockedUrl('blob:https://x.com/1'),
          isFalse);
      expect(
          AdblockService.isBlockedUrl(
              'file:///storage/page.html'),
          isFalse);
    });

    test('main-frame navigations are never blocked', () {
      expect(
          AdblockService.isBlockedUrl('https://doubleclick.net/',
              isMainFrame: true),
          isFalse);
    });

    test('garbage input passes safely', () {
      expect(AdblockService.isBlockedUrl(''), isFalse);
      expect(AdblockService.isBlockedUrl('not a url at all'), isFalse);
    });
  });

  group('hostOf', () {
    test('extracts lowercased host', () {
      expect(AdblockService.hostOf('https://Example.COM/path'),
          'example.com');
    });

    test('returns null for garbage', () {
      expect(AdblockService.hostOf(''), isNull);
      expect(AdblockService.hostOf('::::'), isNull);
    });
  });

  group('BrowserView input routing', () {
    test('plain words are search', () {
      expect(BrowserView.looksLikeSearch('weather dhaka'), isTrue);
      expect(BrowserView.looksLikeSearch('flutter'), isTrue);
    });

    test('address-like input stays a URL', () {
      expect(BrowserView.looksLikeSearch('wikipedia.org'), isFalse);
      expect(
          BrowserView.looksLikeSearch('https://example.com/x'), isFalse);
      expect(BrowserView.looksLikeSearch('localhost:8080'), isFalse);
    });

    test('search URL encodes the query', () {
      expect(BrowserView.searchUrl('weather dhaka'),
          'https://duckduckgo.com/?q=weather+dhaka');
    });
  });

  group('BrowserView.pushCapped', () {
    test('appends normally', () {
      final stack = <String>['a'];
      BrowserView.pushCapped(stack, 'b');
      expect(stack, ['a', 'b']);
    });

    test('drops oldest past the cap', () {
      final stack = <String>['a', 'b'];
      BrowserView.pushCapped(stack, 'c', 2);
      expect(stack, ['b', 'c']);
    });
  });
}
