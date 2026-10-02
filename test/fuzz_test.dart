import 'dart:math';

import 'package:openalias/openalias.dart';
import 'package:test/test.dart';

String encodeValue(String value) {
  final chars = value.split('');
  final out = [
    for (final (i, c) in chars.indexed)
      c == r'\' || c == '"' || (c == ' ' && (i == 0 || i == chars.length - 1))
          ? '\\$c'
          : c
  ].join();
  return value.contains(';') ? '"$out"' : out;
}

void main() {
  test('encoded records round-trip', () {
    final random = Random(1);
    const alphabet = ['a', 'Z', '0', ' ', '"', ';', r'\', '=', 'é', '😀'];
    for (var round = 0; round < 2000; round++) {
      final fields = <String, String>{};
      for (var k = random.nextInt(5); k >= 0; k--) {
        fields['k${fields.length}'] = List.generate(
            random.nextInt(12), (_) => alphabet[random.nextInt(10)]).join();
      }
      final sep = random.nextBool() ? '; ' : ';';
      final record = 'oa1:xmr ${fields.entries.map((e) => '${e.key}='
          '${encodeValue(e.value)}').join(sep)}${random.nextBool() ? ';' : ''}';
      expect(parseOpenAliasRecord(record)!.fields, fields, reason: record);
    }
  });
  test('arbitrary input fails only with OpenAliasException', () {
    final random = Random(2);
    const alphabet = [
      'oa1:xmr ',
      'recipient_address',
      '=',
      ';',
      r'\',
      '"',
      ' ',
      '\t',
      'a',
      'é',
      '\u0000',
      '\u202e',
      r'\;',
      '="',
      '";',
    ];
    var parsed = 0;
    for (var round = 0; round < 20000; round++) {
      final record =
          'oa1:xmr ${List.generate(random.nextInt(24), (_) => alphabet[random.nextInt(alphabet.length)]).join()}';
      try {
        if (parseOpenAliasRecord(record, application: 'xmr') != null) parsed++;
      } on OpenAliasException catch (e) {
        expect(e.toString(), isNot(contains('recipient_address')));
      }
    }
    expect(parsed, greaterThan(0));
  });
}
