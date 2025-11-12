import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_coach/tools/docs_builder.dart';

void main() {
  test('DocsBuilder generates markdown and HTML mirrors', () async {
    final b = DocsBuilder();
    final res = await b.generateAll(write: true);
    expect(res.errors, isEmpty, reason: 'Docs build should not report errors');
    // Check core artifacts
    expect(File('README.md').existsSync(), true);
    expect(File('README.html').existsSync(), true);
    expect(File('docs/core/USAGE.md').existsSync(), true);
    expect(File('docs/core/USAGE.html').existsSync(), true);
    expect(File('docs/discovery/USAGE.md').existsSync(), true);
    expect(File('docs/discovery/USAGE.html').existsSync(), true);
    expect(File('docs/monitor/USAGE.md').existsSync(), true);
    expect(File('docs/monitor/USAGE.html').existsSync(), true);
    expect(File('docs/sdk/USAGE.md').existsSync(), true);
    expect(File('docs/sdk/USAGE.html').existsSync(), true);
    expect(File('docs/build_report.txt').existsSync(), true);
  });
}
