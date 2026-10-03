# Gates: WHOOP 4 Android bridge

Scope: Android WHOOP 4 capture, independent HR export, nightly health export, and minimal setup/status application.

- [x] G1: Static analysis passes for the slim application.
  CHECK: C:\Users\Adi\fl41\flutter\bin\flutter.bat analyze --no-pub
  EXPECT: No issues found!
  EVIDENCE: exit=0; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Adi\.t3\worktrees\edge\t3code-0c99a7d0; path=68eab979bcd3/55 entries; output=Analyzing t3code-0c99a7d0... | No issues found! (ran in 7.5s)

- [x] G2: Retained core and bridge regression tests pass.
  CHECK: C:\Users\Adi\fl41\flutter\bin\flutter.bat test --no-pub --concurrency=1
  EXPECT: All tests passed!
  EVIDENCE: exit=0; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Adi\.t3\worktrees\edge\t3code-0c99a7d0; path=68eab979bcd3/55 entries; output=01:40 +1401 ~22: C:/Users/Adi/.t3/worktrees/edge/t3code-0c99a7d0/test/wear_coverage_test.dart: charging inside the scored sleep window the flag carries no confidence penalty for the caller to apply | 01:40 +1402 ~22: All tests passed!

- [x] G3: Android release APK builds.
  CHECK: C:\Users\Adi\fl41\flutter\bin\flutter.bat build apk --release --no-pub
  EXPECT: app-release.apk
  EVIDENCE: exit=0; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Adi\.t3\worktrees\edge\t3code-0c99a7d0; path=68eab979bcd3/55 entries; output=Running Gradle task 'assembleRelease'...                           41.4s | √ Built build\app\outputs\flutter-apk\app-release.apk (56.5MB)

- [x] G4: Native Health Connect and background tests pass.
  CHECK: .\gradlew.bat app:testDebugUnitTest --console=plain
  EXPECT: BUILD SUCCESSFUL
  CWD: android
  EVIDENCE: exit=0; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Adi\.t3\worktrees\edge\t3code-0c99a7d0\android; path=68eab979bcd3/55 entries; output=BUILD SUCCESSFUL in 11s | 174 actionable tasks: 5 executed, 169 up-to-date

- [ ] G5: Physical WHOOP 4 screen-off, reconnect, overnight export and battery behavior are verified.
  EVIDENCE: pending


- [x] G6: The final capture query uses an index and real retention/reset regressions pass.
  CHECK: C:\Users\Adi\fl41\flutter\bin\flutter.bat test --no-pub --concurrency=1 test/bridge_retention_test.dart
  EXPECT: All tests passed!
  EVIDENCE: exit=0; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Adi\.t3\worktrees\edge\t3code-0c99a7d0; path=68eab979bcd3/55 entries; output=*** sqflite warning *** | 00:00 +4: All tests passed!

ABANDON: G5 No physical WHOOP 4 or connected Android phone is available; real screen-off, reconnect, overnight and battery checks require the owner's hardware.
