# Python haiku sandbox repo (dependency fixture)

This fixture is designed to test Unpossible behavior with task dependencies:

- some tasks include explicit `dependsOn`
- some tasks intentionally omit `dependsOn` and should be **discovered** by a ralph, which should then:
  - update `prd.json` to add the missing `dependsOn`
  - append a coordination note to `progress.txt`
  - output `<promise>SKIP</promise>`
