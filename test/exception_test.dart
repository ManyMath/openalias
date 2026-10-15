import 'package:openalias/openalias.dart';
import 'package:test/test.dart';

void main() {
  test('every error code has one named final exception leaf', () {
    final failures = <OpenAliasException>[
      const OpenAliasInvalidNameException('invalid name'),
      const OpenAliasInvalidRecordException('invalid record'),
      const OpenAliasLimitExceededException('limit', maximum: 64, actual: 65),
      const OpenAliasDuplicateFieldException('duplicate'),
      const OpenAliasInvalidAddressException('invalid address'),
      const OpenAliasUnsupportedFieldException('unsupported'),
      const OpenAliasNoRecordException('missing'),
      const OpenAliasAmbiguousException('ambiguous'),
      const OpenAliasQuestionMismatchException('wrong question'),
      const OpenAliasAuthenticationUnavailableException('untrusted'),
    ];

    expect(failures, everyElement(isA<OpenAliasException>()));
    expect(failures.map((failure) => failure.runtimeType).toSet(),
        hasLength(OpenAliasError.values.length));
    expect(failures.map((failure) => failure.code).toSet(),
        OpenAliasError.values.toSet());
  });

  test('structured limit fields and toString remain machine-independent', () {
    const failure =
        OpenAliasLimitExceededException('too many', maximum: 64, actual: 65);

    expect(failure.maximum, 64);
    expect(failure.actual, 65);
    expect(
        failure.toString(),
        'OpenAliasLimitExceededException(code: limitExceeded, maximum: 64, '
        'actual: 65): too many');
    expect(
        const OpenAliasQuestionMismatchException('wrong result').toString(),
        'OpenAliasQuestionMismatchException(code: questionMismatch): '
        'wrong result');
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
