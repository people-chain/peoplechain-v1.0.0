PeopleChain SDK Packaging

Goal
Prepare a reusable Flutter/Dart package (peoplechain_core) from this repository without external tooling at runtime.

Overview
The source lives under lib/peoplechain_core. The package exposes a barrel export at lib/peoplechain_core/peoplechain_core.dart and is self-contained (Isar schemas checked in).

Two options
1) Path dependency (monorepo app uses this repo directly)
   - In your app's pubspec.yaml:
     dependencies:
       peoplechain_core:
         path: ../this-repo/lib/peoplechain_core
   - Import as: import 'package:peoplechain_core/peoplechain_core.dart';

   Note: This path form is suitable for local development but not for publishing.

2) Create a standalone package folder (recommended for sharing/publishing)
   - Create sdk_release/peoplechain_core/lib
   - Copy the entire repo folder lib/peoplechain_core into sdk_release/peoplechain_core/lib/peoplechain_core (preserves checked-in Isar schemas)
   - Add sdk_release/peoplechain_core/pubspec.yaml (template provided)
   - Add README.md (you can adapt USAGE.md) and CHANGELOG.md
   - Verify analyzer locally by running `dart analyze` from inside sdk_release/peoplechain_core
   - Optionally publish to pub.dev or your private registry

Provided files
- peoplechain_core_pubspec.yaml — Template pubspec for the package
- CHANGELOG_TEMPLATE.md — Suggested changelog scaffold

Note
- To keep Dreamflow analyzer output clean, the repository does not include the duplicate package lib/ sources under sdk_release. Follow the copy step above to materialize the package. All generated Isar schemas are already checked in under lib/peoplechain_core.

Publishing notes
- Ensure Dart SDK >=3.0.0
- No build_runner required; Isar schemas are checked in
- Test web/Android/iOS builds before publishing
