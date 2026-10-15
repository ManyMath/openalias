# openalias

OpenAlias (`oa1:`) TXT record parsing and recipient resolution over a
DNSSEC-validating TXT resolver.

## Usage

```dart
import 'package:openalias/openalias.dart';

final resolver = OpenAliasResolver(
  resolver: txtResolver, // a ValidatingTxtResolver
  application: 'xmr',
  validateAddress: isValidMoneroAddress,
);
final recipient = await resolver.resolve('donate@getmonero.org');
print(recipient.address);
```

`normalizeOpenAlias` lowercases an alias and turns `user@domain` into
`user.domain`. `parseOpenAliasRecord` and `selectOpenAliasRecipient` work on
record strings without DNS. Deliberately reported failures are final named
leaves of sealed `OpenAliasException`; its `code` remains typed metadata for
exhaustive mappings, so callers never need to inspect message text.

## Trust model

This package does no networking and no DNSSEC validation. The injected
`ValidatingTxtResolver` is a trusted port: it must return only locally
authenticated answers and must throw for insecure, bogus, indeterminate,
malformed, or unavailable validation. Supplying that resolver is the caller's
trust decision; `TxtAnswer` is not independent proof. `resolve` still binds the
answer's `question` to the normalized alias. `checksum` and `address_signature`
are carried but not verified. `recipient_name` and `tx_description` are
untrusted display text. Records whose
`recipient_address` fails `validateAddress`, or that disagree about the
address for the application, fail the lookup.

## Configuration

- `application`: the `oa1:` prefix, such as `xmr`.
- `resolver`: a trusted local DNSSEC-validating TXT resolver.
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
