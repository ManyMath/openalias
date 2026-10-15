import 'dart:convert';
import 'package:openalias/openalias.dart';
import 'package:test/test.dart';

final class FakeValidatingResolver implements ValidatingTxtResolver {
  final Future<TxtAnswer> Function(String) lookup;
  const FakeValidatingResolver(this.lookup);

  @override
  Future<TxtAnswer> lookupTxt(String name) => lookup(name);
}

TxtAnswer evidence(String domain, List<String> records) =>
    evidenceBytes(domain, records.map(utf8.encode).toList());

TxtAnswer evidenceBytes(String domain, List<List<int>> records) =>
    TxtAnswer(question: domain, records: records);

OpenAliasResolver xmr(List<List<int>> records, {bool allowPaymentId = false}) =>
    OpenAliasResolver(
        application: 'xmr',
        validateAddress: (a) => a == 'valid' || a == 'second',
        allowPaymentId: allowPaymentId,
        resolver: FakeValidatingResolver(
            (domain) async => evidenceBytes(domain, records)));

Matcher throwsCode(OpenAliasError code) =>
    throwsA(isA<OpenAliasException>().having((e) => e.code, 'code', code));

void main() {
  test('parses TXT records after character strings are joined', () async {
    final joined = utf8
        .encode('oa1:xmr recipient_address=valid; recipient_name="Zoë; Ltd";');
    final result = await xmr([joined]).resolve('alice.example');
    expect(result.address, 'valid');
    expect(result.record!.fields['recipient_name'], 'Zoë; Ltd');
  });
  test('ignores unrelated records that are not UTF-8 or are large', () async {
    final result = await xmr([
      [0xff, 0xfe, 0x20],
      utf8.encode('oa1:btc ${'x' * 9000}'),
      [...utf8.encode('oa1:xmrx '), 0xff],
      utf8.encode('oa1:xmr recipient_address=valid;'),
    ]).resolve('alice.example');
    expect(result.address, 'valid');
    expect(result.dns!.question, 'alice.example');
  });
  test('matching records must be UTF-8', () async {
    await expectLater(
        xmr([
          [
            ...utf8.encode('oa1:xmr recipient_address=valid; recipient_name='),
            0xc3
          ]
        ]).resolve('alice.example'),
        throwsCode(OpenAliasError.invalidRecord));
  });
  test('payment IDs are rejected unless the caller handles them', () async {
    final records = [
      utf8.encode('oa1:xmr recipient_address=valid; tx_payment_id=abc;')
    ];
    await expectLater(xmr(records).resolve('alice.example'),
        throwsCode(OpenAliasError.unsupportedField));
    final result =
        await xmr(records, allowPaymentId: true).resolve('alice.example');
    expect(result.record!.paymentId, 'abc');
    expect(
        () => selectOpenAliasRecipient(
            domain: 'alice.example',
            application: 'xmr',
            records: ['oa1:xmr recipient_address=a; tx_payment_id=abc;'],
            validateAddress: (_) => true),
        throwsCode(OpenAliasError.unsupportedField));
    expect(
        () => selectOpenAliasRecipient(
            domain: 'alice.example',
            application: 'xmr',
            records: ['oa1:xmr recipient_address=a; TX_Payment_ID=abc;'],
            validateAddress: (_) => true,
            allowPaymentId: true),
        throwsCode(OpenAliasError.invalidRecord));
  });
  for (final second in [
    'oa1:xmr recipient_address=valid; tx_payment_id=bbb;',
    'oa1:xmr recipient_address=valid; tx_payment_id=aaa; recipient_name=Bob;',
    'oa1:xmr recipient_address=valid;',
  ]) {
    test('conflicting records for one address are ambiguous: $second',
        () async {
      await expectLater(
          xmr([
            utf8.encode('oa1:xmr recipient_address=valid; tx_payment_id=aaa;'),
            utf8.encode(second),
          ], allowPaymentId: true)
              .resolve('alice.example'),
          throwsCode(OpenAliasError.ambiguous));
    });
  }
  test('multiple or partly invalid addresses fail closed', () async {
    await expectLater(
        xmr([
          utf8.encode('oa1:xmr recipient_address=valid;'),
          utf8.encode('oa1:xmr recipient_address=second;'),
        ]).resolve('alice.example'),
        throwsCode(OpenAliasError.ambiguous));
    await expectLater(
        xmr([
          utf8.encode('oa1:xmr recipient_address=valid;'),
          utf8.encode('oa1:xmr recipient_address=testnet;'),
        ]).resolve('alice.example'),
        throwsCode(OpenAliasError.ambiguous));
  });
  test('uses the caller-injected validating resolver without a token',
      () async {
    final resolver = OpenAliasResolver(
        application: 'xmr',
        validateAddress: (a) => a == 'valid',
        resolver: FakeValidatingResolver((domain) async =>
            evidence(domain, ['oa1:xmr recipient_address=valid;'])));
    final result = await resolver.resolve('alice.example');
    expect(result.address, 'valid');
    expect(result.dns!.question, 'alice.example');
  });
  test('propagates validating resolver failures before parsing', () async {
    final failure = StateError('DNSSEC did not authenticate the answer');
    final resolver = OpenAliasResolver(
        application: 'xmr',
        validateAddress: (_) => true,
        resolver: FakeValidatingResolver((_) async => throw failure));
    await expectLater(
        resolver.resolve('alice.example'), throwsA(same(failure)));
  });
  test('selection without a TXT answer retains no resolver result', () {
    final result = selectOpenAliasRecipient(
        domain: 'alice.example',
        application: 'xmr',
        records: ['oa1:xmr recipient_address=a;'],
        validateAddress: (_) => true);
    expect(result.dns, isNull);
    expect(
        () => selectOpenAliasRecipient(
            domain: 'alice.example',
            application: 'XMR',
            records: const [],
            validateAddress: (_) => true),
        throwsArgumentError);
  });
  test('resolves arbitrary applications and retains DNS provenance', () async {
    final resolver = OpenAliasResolver(
        application: 'btc',
        validateAddress: (a) => a == 'bitcoin',
        resolver: FakeValidatingResolver((domain) async => evidence(domain, [
              'oa1:xmr recipient_address=monero;',
              'oa1:btc recipient_address=bitcoin;custom_1=value;tx_amount=99;'
            ])));
    final result = await resolver.resolve('Alice@Example.');
    expect(result.address, 'bitcoin');
    expect(result.domain, 'alice.example');
    expect(result.application, 'btc');
    expect(result.record!.fields['custom_1'], 'value');
    expect(result.dns!.question, 'alice.example');
    expect(
        () => result.record!.fields['tx_amount'] = '1', throwsUnsupportedError);
  });
  test('rejects authenticated evidence for a different domain', () async {
    final resolver = OpenAliasResolver(
        application: 'xmr',
        validateAddress: (_) => true,
        resolver: FakeValidatingResolver((_) async =>
            evidence('attacker.example', ['oa1:xmr recipient_address=bad;'])));
    await expectLater(
        resolver.resolve('alice.example'),
        throwsA(isA<OpenAliasException>()
            .having((e) => e.code, 'code', OpenAliasError.questionMismatch)));
  });
  test('invalid input does not call lookup', () async {
    var calls = 0;
    final resolver = OpenAliasResolver(
        application: 'xmr',
        validateAddress: (_) => true,
        resolver: FakeValidatingResolver((domain) async {
          calls++;
          return evidence(domain, []);
        }));
    await expectLater(resolver.resolve('https://alice.example'),
        throwsA(isA<OpenAliasException>()));
    expect(calls, 0);
  });
  test('duplicate identical addresses are unambiguous', () {
    expect(
        selectOpenAliasRecipient(
            domain: 'alice.example',
            application: 'xmr',
            records: [
              'oa1:xmr recipient_address=same;',
              'oa1:xmr recipient_address=same;'
            ],
            validateAddress: (_) => true).address,
        'same');
  });
  test('explicit first policy differs from strict default', () {
    const records = [
      'oa1:xmr recipient_address=one;',
      'oa1:xmr recipient_address=two;'
    ];
    expect(
        selectOpenAliasRecipient(
                domain: 'alice.example',
                application: 'xmr',
                records: records,
                validateAddress: (_) => true,
                selection: OpenAliasSelection.first)
            .address,
        'one');
    expect(
        () => selectOpenAliasRecipient(
            domain: 'alice.example',
            application: 'xmr',
            records: records,
            validateAddress: (_) => true),
        throwsA(isA<OpenAliasException>()));
  });
  test('quoted semicolons, embedded quotes and escaped boundary spaces', () {
    final r = parseOpenAliasRecord(
        r'oa1:custom recipient_address=somewhere;recipient_name="Alice; Example";literal=Alice "Example";spaces=\ padded\ ;')!;
    expect(r.application, 'custom');
    expect(r.fields['recipient_name'], 'Alice; Example');
    expect(r.fields['literal'], 'Alice "Example"');
    expect(r.fields['spaces'], ' padded ');
    expect(
        parseOpenAliasRecord(r'oa1:xmr recipient_name="a\"b";')!
            .fields['recipient_name'],
        'a"b');
  });
  test('bounds, trailing escapes, controls and duplicate fields fail', () {
    for (final record in [
      'oa1:xmr recipient_address=a;recipient_address=b;',
      'oa1:xmr recipient_address=a\\',
      'oa1:xmr recipient_address=a\n;',
      'oa1:xmr recipient_address=${'a' * 4096};'
    ]) {
      expect(() => parseOpenAliasRecord(record),
          throwsA(isA<OpenAliasException>()));
    }
    expect(
        () => selectOpenAliasRecipient(
            domain: 'alice.example',
            application: 'xmr',
            records: List.filled(65, 'oa1:xmr recipient_address=a;'),
            validateAddress: (_) => true),
        throwsA(isA<OpenAliasException>()));
  });
}
