import 'dart:io';

import 'package:pocket_coach/tools/docs_builder.dart';

Future<void> main(List<String> args) async {
  stdout.writeln('[docs] Running one-off docs build...');
  final res = await DocsBuilder().generateAll(write: true);
  stdout.writeln('[docs] Wrote ${res.written.length} files, validated ${res.validatedLinks.length} links');
  if (res.errors.isEmpty) {
    stdout.writeln('[docs] Success. Report at docs/build_report.txt');
  } else {
    stderr.writeln('[docs] Completed with ${res.errors.length} error(s):');
    for (final e in res.errors) {
      stderr.writeln(' - $e');
    }
    // Exit non-zero to surface validation failures in CI if used
    exitCode = 2;
  }
}
