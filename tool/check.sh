#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
dart pub get --no-example
dart format --output=none --set-exit-if-changed lib test tool example
dart analyze --fatal-infos lib test tool example
dart test --reporter expanded
dart pub publish --dry-run
dart --packages=.dart_tool/package_config.json example/openalias_example.dart
