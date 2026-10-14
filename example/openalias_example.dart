import 'package:openalias/openalias.dart';

void main() {
  final record = parseOpenAliasRecord(
    'oa1:example recipient_address=demo; recipient_name="Alice; Example";',
  );
  print(record?.application);
  print(record?.fields['recipient_name']);
}
