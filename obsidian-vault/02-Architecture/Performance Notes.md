# Performance Notes

## Known Performance Risks

- ARMv7 devices are a low-power tier and should not run heavy visual effects.
- Diagnostics must not write frequent normal events synchronously on the UI isolate.
- Message streams now use a bounded live tail plus cursor pagination; remaining proof is device/frame-budget validation on large histories.
- File transfer chunk handling needs lower allocation and persistent file sinks.
- Large call UI trees should avoid unnecessary rebuilds.

## Performance Rules

- Prefer `ref.watch(...select(...))` for frequently changing provider fields.
- Avoid continuous animations on low-power tier.
- Avoid large opacity, blur, and shadow layers in scrollable lists.
- Batch progress and diagnostics updates.

Related: [[Technical Debt]], [[File Transfer]], [[Database Architecture]].
