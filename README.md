# openalias

Pure Dart parser and recipient selector for OpenAlias (`oa1:`) TXT records.
No networking, no dependencies.

```dart
import 'package:openalias/openalias.dart';

final domain = normalizeOpenAlias('donate@getmonero.org');
final recipient = selectOpenAliasRecipient(
  domain: domain,
  records: txtRecords, // decoded TXT strings for [domain]
  application: 'xmr',
  validateAddress: isValidMoneroAddress,
);
print(recipient.address);
```

- `normalizeOpenAlias` lowercases an alias and turns `user@domain` into
  `user.domain`. Non-ASCII names must be given as punycode.
- `parseOpenAliasRecord` parses one record and returns null for records of
  another application.
- `selectOpenAliasRecipient` ignores records of other applications and
  requires one valid address. `selection: first` stops at the first matching
  record; `tx_payment_id` is rejected unless `allowPaymentId` is set;
  `validateRecord` adds field checks. At most 64 records are accepted.
- Failures are final leaves of sealed `OpenAliasException`. Messages are
  diagnostics; map the types to your own text.

`checksum` and `address_signature` are carried but not verified.
`recipient_name` and `tx_description` are untrusted display text. Fetching
TXT records and deciding whether to trust them is the caller's job.

## Development

`dart tool/check.dart` runs format, analyze, tests and `pub publish --dry-run`.

## License

MIT; see `LICENSE`.
