import 'dart:convert';

enum OpenAliasError {
  invalidName,
  invalidRecord,
  limitExceeded,
  duplicateField,
  invalidAddress,
  unsupportedField,
  noRecord,
  ambiguous,
  questionMismatch,
  authenticationUnavailable
}

/// Every deliberately reported OpenAlias parsing, selection, or trust failure.
///
/// Catch a final leaf for control flow. [code] is retained as typed metadata
/// for telemetry and exhaustive mappings; callers never need to inspect
/// [message] or [toString].
sealed class OpenAliasException implements Exception {
  final OpenAliasError code;
  final String message;
  const OpenAliasException(this.code, this.message);

  @override
  String toString() => '$runtimeType(code: ${code.name}): $message';
}

final class OpenAliasInvalidNameException extends OpenAliasException {
  const OpenAliasInvalidNameException(String message)
      : super(OpenAliasError.invalidName, message);
}

final class OpenAliasInvalidRecordException extends OpenAliasException {
  const OpenAliasInvalidRecordException(String message)
      : super(OpenAliasError.invalidRecord, message);
}

final class OpenAliasLimitExceededException extends OpenAliasException {
  final int? maximum;
  final int? actual;
  const OpenAliasLimitExceededException(String message,
      {this.maximum, this.actual})
      : super(OpenAliasError.limitExceeded, message);

  @override
  String toString() => '$runtimeType(code: ${code.name}, maximum: $maximum, '
      'actual: $actual): $message';
}

final class OpenAliasDuplicateFieldException extends OpenAliasException {
  const OpenAliasDuplicateFieldException(String message)
      : super(OpenAliasError.duplicateField, message);
}

final class OpenAliasInvalidAddressException extends OpenAliasException {
  const OpenAliasInvalidAddressException(String message)
      : super(OpenAliasError.invalidAddress, message);
}

final class OpenAliasUnsupportedFieldException extends OpenAliasException {
  const OpenAliasUnsupportedFieldException(String message)
      : super(OpenAliasError.unsupportedField, message);
}

final class OpenAliasNoRecordException extends OpenAliasException {
  const OpenAliasNoRecordException(String message)
      : super(OpenAliasError.noRecord, message);
}

final class OpenAliasAmbiguousException extends OpenAliasException {
  const OpenAliasAmbiguousException(String message)
      : super(OpenAliasError.ambiguous, message);
}

final class OpenAliasQuestionMismatchException extends OpenAliasException {
  const OpenAliasQuestionMismatchException(String message)
      : super(OpenAliasError.questionMismatch, message);
}

final class OpenAliasAuthenticationUnavailableException
    extends OpenAliasException {
  const OpenAliasAuthenticationUnavailableException(String message)
      : super(OpenAliasError.authenticationUnavailable, message);
}

/// A TXT answer whose DNS character-strings have already been joined.
final class TxtAnswer {
  final String question;
  final List<List<int>> records;

  /// Set only by the component that performed the DNSSEC validation, never by
  /// glue code; [OpenAliasResolver] accepts it by [identical] comparison with
  /// its `trustedValidators`.
  final Object? validator;
  const TxtAnswer(
      {required this.question, required this.records, required this.validator});
}

/// Resolves TXT records for a normalized DNS name.
abstract interface class TxtResolver {
  Future<TxtAnswer> lookupTxt(String name);
}

/// A TXT resolver that performs local DNSSEC validation.
abstract interface class ValidatingTxtResolver implements TxtResolver {}

final _label = RegExp(r'^[a-z0-9_](?:[a-z0-9_-]{0,61}[a-z0-9_])?$');
final _tld = RegExp(r'^[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$');
const _specialUseTlds = {
  'alt',
  'exit',
  'i2p',
  'invalid',
  'local',
  'localhost',
  'onion',
};

String normalizeOpenAlias(String input) {
  const invalid = OpenAliasInvalidNameException(
      'Enter a valid domain. Use punycode for international names.');
  if (input.length > 1024) throw invalid;
  // Before trim(): it also strips U+00A0, U+FEFF, U+2028 and similar.
  if (input.codeUnits.any((code) => code > 0x7f)) {
    throw const OpenAliasInvalidNameException(
        'Use punycode for international domain names.');
  }
  if (input.codeUnits.any((code) => code < 0x20 || code == 0x7f)) {
    throw invalid;
  }
  var name = input.trim().toLowerCase();
  if (name.split('@').length > 2) {
    throw const OpenAliasInvalidNameException(
        'Enter a domain or an email-style OpenAlias.');
  }
  name = name.replaceAll('@', '.');
  if (name.endsWith('.')) name = name.substring(0, name.length - 1);
  final labels = name.split('.');
  if (name.length > 253 ||
      labels.length < 2 ||
      !labels.every(_label.hasMatch) ||
      !_tld.hasMatch(labels.last) ||
      _specialUseTlds.contains(labels.last)) {
    throw invalid;
  }
  return name;
}

class OpenAliasRecord {
  final String application;

  /// `checksum` and `address_signature` are carried but not verified;
  /// `recipient_name` and `tx_description` are untrusted display text.
  final Map<String, String> fields;
  OpenAliasRecord(this.application, Map<String, String> fields)
      : fields = Map.unmodifiable(fields);
  String? get address => fields['recipient_address'];
  String? get paymentId => fields['tx_payment_id'];
}

class OpenAliasRecipient {
  final String domain;
  final String address;
  final String? application;
  final OpenAliasRecord? record;
  final TxtAnswer? dns;
  const OpenAliasRecipient(
      {required this.domain,
      required this.address,
      this.application,
      this.record,
      this.dns});
}

final _prefix = RegExp(r'oa1:([a-z0-9][a-z0-9_-]*)(?=[ \t]|$)');
final _key = RegExp(r'^[A-Za-z0-9_]+$');
const _standardKeys = {
  'recipient_address',
  'recipient_name',
  'tx_description',
  'tx_amount',
  'tx_payment_id',
  'address_signature',
  'checksum',
};
const _tab = 0x09, _space = 0x20, _quote = 0x22, _semi = 0x3b, _eq = 0x3d;
const _backslash = 0x5c;

bool _blank(int c) => c == _space || c == _tab;

// C0/C1 controls, line separators, zero-width and bidi format characters.
bool _forbidden(int c) =>
    (c < 0x20 && c != _tab) ||
    (c >= 0x7f && c <= 0x9f) ||
    c == 0x061c ||
    c == 0x180e ||
    (c >= 0x200b && c <= 0x200f) ||
    (c >= 0x2028 && c <= 0x202e) ||
    (c >= 0x2060 && c <= 0x2069) ||
    c == 0xfeff ||
    (c >= 0xfff9 && c <= 0xfffb);

// OpenAlias spec: ';' only in a fully quoted value; other quotes are literal.
int _wrapEnd(String s, int open) {
  for (var j = open + 1; j < s.length; j++) {
    final c = s.codeUnitAt(j);
    if (c == _backslash) {
      j++;
    } else if (c == _quote) {
      var k = j + 1;
      while (k < s.length && _blank(s.codeUnitAt(k))) {
        k++;
      }
      if (k == s.length ||
          s.codeUnitAt(k) == _semi ||
          (s.codeUnitAt(k) == _backslash &&
              k + 1 < s.length &&
              s.codeUnitAt(k + 1) == _semi)) {
        return j;
      }
    }
  }
  return -1;
}

// OpenAlias spec: DNS libraries may escape the pair-ending ';' as '\;'.
OpenAliasRecord? parseOpenAliasRecord(String record, {String? application}) {
  final prefix = _prefix.matchAsPrefix(record);
  if (prefix == null || (application != null && prefix[1] != application)) {
    return null;
  }
  if (record.length > 4096) {
    throw OpenAliasLimitExceededException('The OpenAlias record is too large.',
        maximum: 4096, actual: record.length);
  }
  const malformed =
      OpenAliasInvalidRecordException('The OpenAlias record is malformed.');
  if (record.codeUnits.any(_forbidden)) throw malformed;
  final n = record.length;
  final fields = <String, String>{};
  final seen = <String>{};
  var i = prefix.end;
  while (true) {
    while (i < n) {
      final c = record.codeUnitAt(i);
      if (_blank(c) || c == _semi) {
        i++;
      } else if (c == _backslash &&
          i + 1 < n &&
          record.codeUnitAt(i + 1) == _semi) {
        i += 2;
      } else {
        break;
      }
    }
    if (i == n) break;
    final start = i;
    while (i < n &&
        record.codeUnitAt(i) != _eq &&
        record.codeUnitAt(i) != _semi &&
        record.codeUnitAt(i) != _backslash) {
      i++;
    }
    if (i == n || record.codeUnitAt(i) != _eq) throw malformed;
    final key = _trimBlanks(record.substring(start, i));
    if (!_key.hasMatch(key) ||
        (key != key.toLowerCase() &&
            _standardKeys.contains(key.toLowerCase()))) {
      throw malformed;
    }
    if (!seen.add(key.toLowerCase())) {
      throw const OpenAliasDuplicateFieldException(
          'Duplicate OpenAlias field.');
    }
    i++;
    while (i < n && _blank(record.codeUnitAt(i))) {
      i++;
    }
    final close =
        i < n && record.codeUnitAt(i) == _quote ? _wrapEnd(record, i) : -1;
    final wrapped = close >= 0;
    final end = wrapped ? close : n;
    final units = <int>[];
    final escaped = <bool>[];
    var j = wrapped ? i + 1 : i;
    while (j < end) {
      final c = record.codeUnitAt(j);
      if (c == _backslash) {
        if (j + 1 >= end) throw malformed;
        final next = record.codeUnitAt(j + 1);
        j += 2;
        if (next == _semi && !wrapped) break;
        if (next != _space &&
            next != _quote &&
            next != _backslash &&
            next != _semi) {
          throw malformed;
        }
        units.add(next);
        escaped.add(true);
      } else {
        j++;
        if (c == _semi && !wrapped) break;
        units.add(c);
        escaped.add(false);
      }
    }
    if (wrapped) {
      j = close + 1;
      while (j < n && _blank(record.codeUnitAt(j))) {
        j++;
      }
      if (j < n) j += record.codeUnitAt(j) == _semi ? 1 : 2;
    }
    i = j;
    var first = 0;
    var last = units.length;
    while (first < last && !escaped[first] && _blank(units[first])) {
      first++;
    }
    while (last > first && !escaped[last - 1] && _blank(units[last - 1])) {
      last--;
    }
    fields[key] = String.fromCharCodes(units.sublist(first, last));
  }
  return OpenAliasRecord(prefix[1]!, fields);
}

String _trimBlanks(String s) {
  var a = 0;
  var b = s.length;
  while (a < b && _blank(s.codeUnitAt(a))) {
    a++;
  }
  while (b > a && _blank(s.codeUnitAt(b - 1))) {
    b--;
  }
  return s.substring(a, b);
}

enum OpenAliasSelection { uniqueAddress, first }

typedef OpenAliasFieldValidator = void Function(OpenAliasRecord record);

final _application = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

void _checkApplication(String application) {
  if (!_application.hasMatch(application)) {
    throw ArgumentError.value(application, 'application');
  }
}

bool _sameFields(OpenAliasRecord a, OpenAliasRecord b) =>
    a.fields.length == b.fields.length &&
    a.fields.entries.every((e) => b.fields[e.key] == e.value);

/// Does not authenticate [records]; use [OpenAliasResolver] for DNS data.
OpenAliasRecipient selectOpenAliasRecipient(
    {required String domain,
    required List<String> records,
    required String application,
    required bool Function(String) validateAddress,
    OpenAliasFieldValidator? validateRecord,
    OpenAliasSelection selection = OpenAliasSelection.uniqueAddress,
    bool allowPaymentId = false,
    TxtAnswer? dns}) {
  _checkApplication(application);
  if (records.length > 64) {
    throw OpenAliasLimitExceededException('Too many DNS records.',
        maximum: 64, actual: records.length);
  }
  final parsed = <OpenAliasRecord>[];
  for (final text in records) {
    final record = parseOpenAliasRecord(text, application: application);
    if (record != null) parsed.add(record);
  }
  final candidates = <String, OpenAliasRecord>{};
  for (final record in parsed) {
    if (!allowPaymentId && (record.paymentId?.isNotEmpty ?? false)) {
      throw const OpenAliasUnsupportedFieldException(
          'This alias requires a separate payment ID, which is not supported.');
    }
    validateRecord?.call(record);
    final address = record.address;
    if (address == null || address.isEmpty || !validateAddress(address)) {
      // A publisher may also list another network's address under this app.
      if (parsed.length > 1) {
        throw const OpenAliasAmbiguousException(
            'The alias has multiple recipient addresses.');
      }
      throw const OpenAliasInvalidAddressException(
          'The alias contains an invalid address for this wallet.');
    }
    final previous = candidates.putIfAbsent(address, () => record);
    if (!_sameFields(previous, record)) {
      throw const OpenAliasAmbiguousException(
          'The alias has conflicting records for one address.');
    }
    if (selection == OpenAliasSelection.first) break;
  }
  if (candidates.isEmpty) {
    throw const OpenAliasNoRecordException(
        'No matching OpenAlias record was found.');
  }
  if (candidates.length != 1) {
    throw const OpenAliasAmbiguousException(
        'The alias has multiple recipient addresses.');
  }
  return OpenAliasRecipient(
      domain: domain,
      address: candidates.keys.single,
      application: application,
      record: candidates.values.single,
      dns: dns);
}

class OpenAliasResolver {
  final ValidatingTxtResolver resolver;
  final String application;
  final bool Function(String) validateAddress;
  final OpenAliasFieldValidator? validateRecord;
  final OpenAliasSelection selection;
  final bool allowPaymentId;
  final List<Object> trustedValidators;
  OpenAliasResolver(
      {required this.resolver,
      required this.application,
      required this.validateAddress,
      required Iterable<Object> trustedValidators,
      this.validateRecord,
      this.selection = OpenAliasSelection.uniqueAddress,
      this.allowPaymentId = false})
      : trustedValidators = List.unmodifiable(trustedValidators) {
    _checkApplication(application);
    if (this.trustedValidators.isEmpty) {
      throw ArgumentError.value(
          trustedValidators, 'trustedValidators', 'Must not be empty');
    }
  }

  Future<OpenAliasRecipient> resolve(String input) async {
    final domain = normalizeOpenAlias(input);
    final result = await resolver.lookupTxt(domain);
    if (result.question != domain) {
      throw const OpenAliasQuestionMismatchException(
          'The DNS result belongs to another alias.');
    }
    if (!trustedValidators.any((v) => identical(v, result.validator))) {
      throw const OpenAliasAuthenticationUnavailableException(
          'The DNS result is from an untrusted validator.');
    }
    if (result.records.length > 64) {
      throw OpenAliasLimitExceededException('Too many DNS records.',
          maximum: 64, actual: result.records.length);
    }
    final prefix = ascii.encode('oa1:$application');
    final records = <String>[];
    for (final bytes in result.records) {
      if (!_hasPrefix(bytes, prefix)) continue;
      try {
        records.add(utf8.decode(bytes));
      } on FormatException {
        throw const OpenAliasInvalidRecordException(
            'The OpenAlias record is malformed.');
      }
    }
    return selectOpenAliasRecipient(
        domain: domain,
        records: records,
        application: application,
        validateAddress: validateAddress,
        validateRecord: validateRecord,
        selection: selection,
        allowPaymentId: allowPaymentId,
        dns: result);
  }
}

bool _hasPrefix(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return bytes.length == prefix.length || _blank(bytes[prefix.length]);
}
