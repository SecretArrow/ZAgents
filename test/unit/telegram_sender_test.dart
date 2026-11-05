import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/services/telegram_sender.dart';

void main() {
  group('TelegramSender', () {
    test('sends chat_id and text to the Bot API and succeeds on ok:true', () async {
      Uri? capturedUri;
      String? capturedBody;
      final TelegramSender sender = TelegramSender(
        client: MockClient((http.Request request) async {
          capturedUri = request.url;
          capturedBody = request.body;
          return http.Response(
            jsonEncode(<String, dynamic>{'ok': true, 'result': <String, dynamic>{}}),
            200,
          );
        }),
      );
      final TelegramSendResult result = await sender.send(
        token: '123:ABC',
        chatId: '42',
        text: 'hello from cron',
      );
      expect(result.ok, isTrue);
      expect(result.error, isNull);
      expect(capturedUri.toString(), 'https://api.telegram.org/bot123:ABC/sendMessage');
      final Map<String, dynamic> body =
          jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(body['chat_id'], '42');
      expect(body['text'], 'hello from cron');
    });

    test('surfaces the Telegram error description on HTTP 400', () async {
      final TelegramSender sender = TelegramSender(
        client: MockClient((http.Request request) async => http.Response(
              jsonEncode(<String, dynamic>{
                'ok': false,
                'error_code': 400,
                'description': 'Bad Request: chat not found',
              }),
              400,
            )),
      );
      final TelegramSendResult result = await sender.send(
        token: '123:ABC',
        chatId: '42',
        text: 'x',
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('chat not found'));
    });

    test('surfaces an unauthorized token as an error', () async {
      final TelegramSender sender = TelegramSender(
        client: MockClient((http.Request request) async => http.Response(
              jsonEncode(<String, dynamic>{
                'ok': false,
                'error_code': 401,
                'description': 'Unauthorized',
              }),
              401,
            )),
      );
      final TelegramSendResult result = await sender.send(
        token: 'bad',
        chatId: '42',
        text: 'x',
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('401'));
    });

    test('network exceptions degrade to a failed result', () async {
      final TelegramSender sender = TelegramSender(
        client: MockClient((http.Request request) async {
          throw http.ClientException('connection refused');
        }),
      );
      final TelegramSendResult result = await sender.send(
        token: '123:ABC',
        chatId: '42',
        text: 'x',
      );
      expect(result.ok, isFalse);
      expect(result.error, isNotNull);
    });

    test('empty credentials or message fail fast without any request', () async {
      var called = false;
      final TelegramSender sender = TelegramSender(
        client: MockClient((http.Request request) async {
          called = true;
          return http.Response('{"ok":true}', 200);
        }),
      );
      expect(
        (await sender.send(token: '', chatId: '1', text: 'x')).ok,
        isFalse,
      );
      expect(
        (await sender.send(token: 't', chatId: '', text: 'x')).ok,
        isFalse,
      );
      expect(
        (await sender.send(token: 't', chatId: '1', text: '  ')).ok,
        isFalse,
      );
      expect(called, isFalse);
    });
  });
}
