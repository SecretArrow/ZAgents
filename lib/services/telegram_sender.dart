import 'dart:convert';

import 'package:http/http.dart' as http;

/// Sends text through the Telegram Bot API — v1.49.9.
///
/// Endpoint: `POST https://api.telegram.org/bot<token>/sendMessage` with a
/// JSON body `{chat_id, text}`. The [http.Client] is injectable so unit
/// tests plug in a [http.MockClient] (same pattern as [UpdateChecker]).
///
/// All failures are returned as data ([TelegramSendResult.ok] == false
/// with a human-readable [TelegramSendResult.error]) instead of thrown —
/// a cron fire must never crash the scheduler.
class TelegramSender {
  TelegramSender({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 20);

  /// Sends [text] to [chatId] using bot [token]. Returns the outcome.
  Future<TelegramSendResult> send({
    required String token,
    required String chatId,
    required String text,
  }) async {
    final String cleanToken = token.trim();
    final String cleanChat = chatId.trim();
    if (cleanToken.isEmpty || cleanChat.isEmpty) {
      return const TelegramSendResult(
        ok: false,
        error: 'bot token / chat id is empty',
      );
    }
    if (text.trim().isEmpty) {
      return const TelegramSendResult(ok: false, error: 'message is empty');
    }
    final Uri uri = Uri.parse(
      'https://api.telegram.org/bot$cleanToken/sendMessage',
    );
    try {
      final http.Response response = await _client
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(<String, dynamic>{
              'chat_id': cleanChat,
              'text': text,
              'disable_web_page_preview': true,
            }),
          )
          .timeout(_timeout);
      final Map<String, dynamic> decoded = _tryDecode(response.body);
      if (response.statusCode == 200 && decoded['ok'] == true) {
        return const TelegramSendResult(ok: true);
      }
      // Telegram error payload: {"ok":false,"error_code":400,
      // "description":"Bad Request: chat not found"}.
      final String description =
          (decoded['description'] as String?) ?? response.body;
      return TelegramSendResult(
        ok: false,
        error: 'HTTP ${response.statusCode}: $description',
      );
    } catch (error) {
      return TelegramSendResult(ok: false, error: '$error');
    }
  }

  Map<String, dynamic> _tryDecode(String body) {
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Non-JSON body: fall through to the raw-body error path.
    }
    return <String, dynamic>{};
  }
}

/// Outcome of one [TelegramSender.send] call.
class TelegramSendResult {
  const TelegramSendResult({required this.ok, this.error});

  final bool ok;

  /// Human-readable failure reason; null on success.
  final String? error;
}
