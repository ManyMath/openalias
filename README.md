# openalias

OpenAlias (`oa1:`) TXT record parsing and recipient resolution over a
DNSSEC-validating TXT resolver.

## Usage

```dart
import 'package:openalias/openalias.dart';

final resolver = OpenAliasResolver(
  resolver: txtResolver, // a ValidatingTxtResolver
  trustedValidators: [DnssecResolver.validator],
  application: 'xmr',
  validateAddress: isValidMoneroAddress,
);
final recipient = await resolver.resolve('donate@getmonero.org');
print(recipient.address);
```

`normalizeOpenAlias` lowercases an alias and turns `user@domain` into
`user.domain`. `parseOpenAliasRecord` and `selectOpenAliasRecipient` work on
record strings without DNS.

## Trust model

This package does no networking and no DNSSEC validation. `resolve` accepts a
`TxtAnswer` only when its `question` is the normalized alias and its
`validator` is `identical` to one of `trustedValidators`; the component that
performed the validation sets `validator`, never glue code. `checksum` and
`address_signature` are carried but not verified. `recipient_name` and
`tx_description` are untrusted display text. Records whose
`recipient_address` fails `validateAddress`, or that disagree about the
address for the application, fail the lookup.

## Configuration

- `application`: the `oa1:` prefix, such as `xmr`.
- `validateAddress`: the wallet's address check. `validateRecord` adds field
  checks.
- `selection`: `uniqueAddress` (default) requires one address across matching
  records; `first` stops at the first matching record.
- `allowPaymentId`: `tx_payment_id` fails the lookup unless set.

## Development

`bash tool/check.sh` runs format, analyze, the tests, `pub publish --dry-run`
and the example. No network access is needed.

## License

MIT; see `LICENSE`.
