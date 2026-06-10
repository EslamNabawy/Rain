<!-- android-flutter-qa:start -->
## Local Android Flutter QA

Use the shared Windows QA toolkit at `C:\android-flutter-qa-toolkit` for local Android validation.

Rules:
- Use PowerShell commands only; do not use bash.
- Do not use Docker for this local workflow.
- Keep Appium bound to `127.0.0.1:4723`.
- Prefer Flutter `integration_test` for durable app flows.
- Use Appium + `appium-flutter-driver` only for external smoke/cross-tool automation.
- Run the project smoke through `qa.appium.json`; do not create per-project `node_modules` for Appium.
- Interactive widgets that automation touches need stable `ValueKey('qa.feature.action')`.
- Widgets that native/black-box automation must see also need `Semantics`.
- Store run artifacts under `D:\android-test-artifacts`.
- Do not touch `D:\old project\Rain`.

Common commands:
```powershell
C:\android-flutter-qa-toolkit\scripts\test-env.ps1
C:\android-flutter-qa-toolkit\scripts\start-avd.ps1
C:\android-flutter-qa-toolkit\scripts\start-appium.ps1
C:\android-flutter-qa-toolkit\scripts\run-local-quality.ps1 -ProjectRoot "<project-root>"
C:\android-flutter-qa-toolkit\scripts\run-local-quality.ps1 -ProjectRoot "<project-root>" -IncludeIntegration -Udid emulator-5554
C:\android-flutter-qa-toolkit\scripts\run-appium-smoke.ps1 -ProjectRoot "<project-root>" -BuildFirst -StartAvd -StartAppium
```

<!-- android-flutter-qa:end -->

