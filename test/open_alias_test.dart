import 'package:test/test.dart';
import 'package:openalias/openalias.dart';

OpenAliasRecipient select(List<String> records) => selectOpenAliasRecipient(
      domain: 'alice.example',
      application: 'xmr',
      validateRecord: rejectPaymentId,
      records: records,
      validateAddress: (s) => s == 'valid' || s == 'second',
    );

void rejectPaymentId(OpenAliasRecord record) {
  if (record.fields['tx_payment_id']?.isNotEmpty ?? false) {
    throw const OpenAliasException(OpenAliasError.unsupportedField,
        'Separate payment IDs are unsupported');
  }
}

void main() {
  parserTests();
  test('normalizes email aliases, case and root dot', () {
    expect(normalizeOpenAlias(' Alice@Example. '), 'alice.example');
    expect(normalizeOpenAlias(' alice.example'), 'alice.example');
    expect(normalizeOpenAlias('alice.example '), 'alice.example');
    expect(
      normalizeOpenAlias('xn--bcher-kva.example'),
      'xn--bcher-kva.example',
    );
    expect(normalizeOpenAlias('Dan_M@_Pay.Example'), 'dan_m._pay.example');
    expect(normalizeOpenAlias('pay.xn--p1ai'), 'pay.xn--p1ai');
    final long = '${'a' * 63}.${'b' * 63}.${'c' * 63}.${'d' * 57}.org';
    expect(long.length, 253);
    expect(normalizeOpenAlias('$long.'), long);
  });
  for (final name in [
    'example',
    'https://example.org',
    'a@@b.org',
    'a..org',
    'a.org/path',
    '-a.org',
    'ü.example',
    'K.example',
    '127.0.0.1',
    'a.onion',
    'a.org\u0000',
    '\ufeffalice.example',
    '\u00a0alice.example',
    'alice.example\u2028',
    'alice.example\u3000',
    '\talice.example',
    'alice.example\n',
    'alice.exam\u007fple',
    'alice@',
    '@example.org',
    'a.org..',
    'a b.org',
    'a\u3002org',
    '[::1]',
    '1.2.3.4.',
    'example.123',
    'alice.b_c',
    'x.onion.',
    'alice@pay.localhost',
    'printer.local',
    'a.i2p',
    'a.exit',
    'a.alt',
    'a.invalid',
    '${'a' * 64}.org',
    '${'a' * 63}.${'b' * 63}.${'c' * 63}.${'d' * 58}.org',
    '${'a.' * 600}org',
  ]) {
    test('rejects invalid alias ${name.length > 40 ? name.length : name}', () {
      expect(
        () => normalizeOpenAlias(name),
        throwsA(isA<OpenAliasException>()),
      );
    });
  }
  test(
    'parses semicolon fields and quoted values without requiring spaces',
    () {
      expect(
        select([
          'oa1:xmr recipient_name="Alice; Example";recipient_address="valid";',
        ]).address,
        'valid',
      );
    },
  );
  test('ignores other coins and nonmatching currency prefixes', () {
    expect(
      select([
        'oa1:btc recipient_address=bad;',
        'oa1:xmrfoo recipient_address=bad;',
        'oa1:xmr recipient_address=valid;',
      ]).address,
      'valid',
    );
  });
  for (final records in [
    <String>[],
    ['oa1:xmr recipient_address=wrong-network;'],
    ['oa1:xmr recipient_address=valid;recipient_address=second;'],
    ['oa1:xmr recipient_address=valid;', 'oa1:xmr recipient_address=second;'],
    ['oa1:xmr recipient_address=valid;tx_payment_id=0123456789abcdef;'],
    ['oa1:xmr recipient_address="valid;'],
  ]) {
    test(
      'rejects missing, invalid or ambiguous payment instructions $records',
      () {
        expect(() => select(records), throwsA(isA<OpenAliasException>()));
      },
    );
  }
  test('blames the alias only when its single address is invalid', () {
    OpenAliasError code(List<String> records) {
      try {
        select(records);
      } on OpenAliasException catch (e) {
        return e.code;
      }
      fail('expected an exception');
    }

    expect(code(['oa1:xmr recipient_address=wrong-network;']),
        OpenAliasError.invalidAddress);
    expect(
        code([
          'oa1:xmr recipient_address=valid;',
          'oa1:xmr recipient_address=wrong-network;',
        ]),
        OpenAliasError.ambiguous);
    expect(
        code([
          'oa1:xmr recipient_address=wrong-network;',
          'oa1:xmr recipient_address=valid;',
        ]),
        OpenAliasError.ambiguous);
  });
  test('does not apply suggested amounts or names to recipient', () {
    final result = select([
      'oa1:xmr recipient_address=valid;tx_amount=999;recipient_name=Someone;',
    ]);
    expect(result.domain, 'alice.example');
    expect(result.address, 'valid');
  });
}

Map<String, String> fields(String record) =>
    parseOpenAliasRecord(record, application: 'xmr')!.fields;

void parserTests() {
  group('record parser', () {
    test('keeps quotes that do not wrap the whole value', () {
      expect(
        fields('oa1:xmr recipient_address=a; '
            'recipient_name=Alice "Vendor" Smith;')['recipient_name'],
        'Alice "Vendor" Smith',
      );
      expect(fields('oa1:xmr recipient_name=O"Brien;')['recipient_name'],
          'O"Brien');
      expect(fields('oa1:xmr recipient_name="O"Brien";')['recipient_name'],
          'O"Brien');
      expect(
          fields('oa1:xmr recipient_name="Alice" Smith; recipient_address=a;'),
          {'recipient_name': '"Alice" Smith', 'recipient_address': 'a'});
      expect(fields('oa1:xmr recipient_name="Bob; recipient_address=a;'),
          {'recipient_name': '"Bob', 'recipient_address': 'a'});
    });
    test('allows semicolons only in fully wrapped values', () {
      expect(
          fields('oa1:xmr recipient_name = "  Alice; Bob  " ; '
              'recipient_address="a"'),
          {'recipient_name': 'Alice; Bob', 'recipient_address': 'a'});
      expect(fields('oa1:xmr tx_description="a;b;c";recipient_address=a;'),
          {'tx_description': 'a;b;c', 'recipient_address': 'a'});
      expect(() => fields('oa1:xmr recipient_name=Alice; Smith;'),
          throwsA(isA<OpenAliasException>()));
      expect(() => fields('oa1:xmr recipient_name=Alice "a;b" Smith;'),
          throwsA(isA<OpenAliasException>()));
    });
    test('accepts backslash-escaped pair separators', () {
      expect(fields(r'oa1:xmr recipient_address=a\; recipient_name=b\;'),
          {'recipient_address': 'a', 'recipient_name': 'b'});
      expect(fields(r'oa1:xmr recipient_name="x\;y" \; recipient_address=a\;'),
          {'recipient_name': 'x;y', 'recipient_address': 'a'});
    });
    test('escapes, trimming, empty values and keys', () {
      expect(
          fields('oa1:xmr\trecipient_address=\ta\t; Custom_1=; e="";'
              r' q=\"x\"; b=a\\b; s=\ \ '),
          {
            'recipient_address': 'a',
            'Custom_1': '',
            'e': '',
            'q': '"x"',
            'b': r'a\b',
            's': '  ',
          });
      expect(fields('oa1:xmr recipient_name=Zoë 山田 😀;')['recipient_name'],
          'Zoë 山田 😀');
    });
    for (final (i, record) in [
      'oa1:xmr recipient_address=a;Recipient_Address=b;',
      r'oa1:xmr recipient_name=a\nb;',
      r'oa1:xmr recipient_name=a\',
      'oa1:xmr recipient_name=a\u202eb;',
      'oa1:xmr recipient_name=a\u2067b;',
      'oa1:xmr recipient_name=a\u0085b;',
      'oa1:xmr recipient_name=a\u200bb;',
      'oa1:xmr recipient_name=a\u200fb;',
      'oa1:xmr recipient_name=a\u061cb;',
      'oa1:xmr recipient_name=a\u2060b;',
      'oa1:xmr recipient_name=a\u2064b;',
      'oa1:xmr recipient_name=a\ufeffb;',
      'oa1:xmr recipient_name=a\ufff9b;',
      'oa1:xmr recipient_name=a\u180eb;',
      'oa1:xmr recipient_address=\u200ba;',
      'oa1:xmr tx_description="a\u202ab";',
      'oa1:xmr recipient_name=a\rb;',
      'oa1:xmr recipient address=a;',
      'oa1:xmr recipient_address=a; junk;',
      'oa1:xmr =a;',
      'oa1:xmr "recipient_address"=a;',
      r'oa1:xmr recipient\_address=a;',
      'oa1:xmr recipient_address=${'a' * 4096}',
    ].indexed) {
      test('rejects malformed record $i', () {
        expect(() => fields(record), throwsA(isA<OpenAliasException>()));
      });
    }
    test('ignores other records without inspecting them', () {
      for (final record in [
        'oa1:xmrfoo recipient_address=a;',
        'OA1:xmr recipient_address=a;',
        ' oa1:xmr recipient_address=a;',
        'oa1:xmr;recipient_address=a;',
        'v=spf1 -all',
        'oa1:btc recipient_address=\u0000${'a' * 70000}',
        'x' * 70000,
      ]) {
        expect(parseOpenAliasRecord(record, application: 'xmr'), isNull);
      }
    });
    test('errors do not echo record contents', () {
      try {
        fields('oa1:xmr recipient_address=secret;recipient_address=secret2;');
        fail('expected an exception');
      } on OpenAliasException catch (e) {
        expect(e.toString(), isNot(contains('secret')));
      }
    });
  });
}
