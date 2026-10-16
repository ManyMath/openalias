import 'package:openalias/openalias.dart';
import 'package:test/test.dart';

void main() {
  test('every leaf is a distinct final exception type', () {
    final failures = <OpenAliasException>[
      const OpenAliasInvalidNameException('invalid name'),
      const OpenAliasInvalidRecordException('invalid record'),
      const OpenAliasLimitExceededException('limit', maximum: 64, actual: 65),
      const OpenAliasDuplicateFieldException('duplicate'),
      const OpenAliasInvalidAddressException('invalid address'),
      const OpenAliasUnsupportedFieldException('unsupported'),
      const OpenAliasNoRecordException('missing'),
      const OpenAliasAmbiguousException('ambiguous'),
    ];

    expect(failures.map((failure) => failure.runtimeType).toSet(),
        hasLength(failures.length));
    expect(failures.map((failure) => failure.toString()),
        contains('OpenAliasNoRecordException: missing'));
  });

  test('cause is carried but never printed', () {
    final trace = StackTrace.current;
    final failure = OpenAliasInvalidRecordException('bad',
        cause: StateError('secret-detail'), causeStackTrace: trace);

    expect(failure.cause, isA<StateError>());
    expect(failure.causeStackTrace, same(trace));
    expect(failure.toString(), 'OpenAliasInvalidRecordException: bad');
    expect(const OpenAliasAmbiguousException('x').cause, isNull);
  });

  test('limit fields and toString', () {
    const failure =
        OpenAliasLimitExceededException('too many', maximum: 64, actual: 65);

    expect(failure.maximum, 64);
    expect(failure.actual, 65);
    expect(failure.toString(),
        'OpenAliasLimitExceededException(maximum: 64, actual: 65): too many');
  });

  test('public operations report named leaves rather than a generic root', () {
    expect(() => normalizeOpenAlias('https://example.com'),
        throwsA(isA<OpenAliasInvalidNameException>()));
    expect(() => parseOpenAliasRecord('oa1:xmr recipient_address'),
        throwsA(isA<OpenAliasInvalidRecordException>()));
    expect(
        () => selectOpenAliasRecipient(
            domain: 'example.com',
            records: const [],
            application: 'xmr',
            validateAddress: (_) => true),
        throwsA(isA<OpenAliasNoRecordException>()));
  });
}
