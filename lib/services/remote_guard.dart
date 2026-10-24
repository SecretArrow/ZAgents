import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Thrown by [RemoteGuard] when a URL or download is rejected.
class RemoteGuardException implements Exception {
  const RemoteGuardException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// URL and download policy for user/agent supplied remote content (skills,
/// npm packages, module archives).
///
/// Two threats are handled here, both reachable from the chat:
///  * **SSRF** — a source like `https://127.0.0.1:8080` or
///    `http://192.168.1.1` would make the device fetch its own local
///    services or the user's LAN (routers, NAS, admin panels).
///  * **Resource exhaustion** — an endpoint that streams forever, or an
///    archive that expands without bound, must not be able to fill memory.
class RemoteGuard {
  const RemoteGuard._();

  /// True only for public `https` endpoints.
  static bool isAllowedUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    String host = uri.host.toLowerCase();
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    if (host.isEmpty) return false;
    if (host == 'localhost' || host.endsWith('.localhost')) return false;
    final RegExp ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
    final Match? match = ipv4.firstMatch(host);
    if (match != null) {
      final List<int> parts = <int>[
        for (int i = 1; i <= 4; i++) int.parse(match.group(i)!),
      ];
      if (parts.any((int p) => p > 255)) return false;
      final int a = parts[0];
      final int b = parts[1];
      if (a == 0 || a == 10 || a == 127) return false;
      if (a == 169 && b == 254) return false; // link-local
      if (a == 172 && b >= 16 && b <= 31) return false; // private
      if (a == 192 && b == 168) return false; // private
      if (a == 100 && b >= 64 && b <= 127) return false; // CGNAT
      if (a >= 224) return false; // multicast / reserved
      return true;
    }
    if (host.contains(':')) {
      // IPv4-mapped IPv6 (`::ffff:127.0.0.1`) reaches the same address as
      // the bare literal, so it must be judged by the IPv4 rules.
      final String mapped = host.startsWith('::ffff:')
          ? host.substring('::ffff:'.length)
          : '';
      if (mapped.isNotEmpty && ipv4.hasMatch(mapped)) {
        return isAllowedUrl('https://$mapped/');
      }
      // IPv6 literals: loopback, link-local, unique-local.
      if (host == '::1' || host == '::' || host.startsWith('fe80')) {
        return false;
      }
      if (host.startsWith('fc') || host.startsWith('fd')) return false;
    }
    return true;
  }

  /// Downloads [uri] with a hard byte cap and per-hop URL validation.
  ///
  /// The `http` client follows redirects on its own, which would let an
  /// allowed https URL bounce to `http://` or to `http://192.168.x.x` after
  /// the initial check. Redirects are therefore followed manually, and the
  /// body is capped while streaming so a hostile endpoint cannot exhaust
  /// memory by declaring a small Content-Length and then sending forever.
  static Future<List<int>> download(
    http.Client client,
    Uri uri, {
    Map<String, String>? headers,
    required int maxBytes,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    Uri current = uri;
    for (int hop = 0; hop < 5; hop++) {
      if (!isAllowedUrl(current.toString())) {
        throw RemoteGuardException(
          'Refusing to download from an untrusted URL: $current '
          '(https on a public host is required).',
        );
      }
      final http.Request request = http.Request('GET', current);
      if (headers != null) request.headers.addAll(headers);
      final http.StreamedResponse response = await client
          .send(request)
          .timeout(timeout);
      if (response.isRedirect) {
        final String? location = response.headers['location'];
        await response.stream.drain<void>();
        if (location == null || location.isEmpty) {
          throw RemoteGuardException(
            'Redirect without a Location header from $current',
          );
        }
        current = current.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw RemoteGuardException(
          'Download failed: HTTP ${response.statusCode} for $current',
        );
      }
      final int? declared = response.contentLength;
      if (declared != null && declared > maxBytes) {
        await response.stream.drain<void>();
        throw RemoteGuardException(
          'Download exceeds the ${_mb(maxBytes)} MB limit.',
        );
      }
      final BytesBuilder builder = BytesBuilder(copy: false);
      await for (final List<int> chunk in response.stream) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw RemoteGuardException(
            'Download exceeds the ${_mb(maxBytes)} MB limit.',
          );
        }
      }
      return builder.takeBytes();
    }
    throw RemoteGuardException('Too many redirects for $uri');
  }

  static int _mb(int bytes) => (bytes / (1024 * 1024)).round();
}
