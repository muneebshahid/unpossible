# Tests / Sandbox Fixtures

This repo is mostly shell scripts, but we keep a small **sandbox fixture repo** to test Unpossible end-to-end.

## Create the sandbox repo in `/tmp/unp`

```bash
# Independent-tasks fixture (default)
./tests/create-sandbox-repo.sh /tmp/unp --force

# Dependency fixture (mixed explicit dependsOn + SKIP flow)
./tests/create-sandbox-repo.sh /tmp/unp --force --fixture python-haiku-deps-repo
```

## Run the sandbox baseline tests

```bash
cd /tmp/unp
python -m unittest discover -s tests
```

## Run Unpossible against the 7-task PRD

```bash
cd /tmp/unp
./unpossible.sh 2 10 haiku
```

If tasks are pending but blocked by dependencies, ralphs wait and retry. Override the sleep interval:

```bash
cd /tmp/unp
WAIT_SECONDS=60 ./unpossible.sh 2 10 haiku
```

## Check completion

```bash
cd /tmp/unp
jq '.[] | {id, done, dependsOn, lastUpdatedBy, lastUpdatedAt, notes}' prd.json
tail -n +1 progress.txt
python -m unittest discover -s tests
```
