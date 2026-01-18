# Tests / Sandbox Fixtures

This repo is mostly shell scripts, but we keep a small **sandbox fixture repo** to test Unpossible end-to-end.

## Create the sandbox repo in `/tmp/unp`

```bash
./tests/create-sandbox-repo.sh /tmp/unp
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

## Check completion

```bash
cd /tmp/unp
jq '.[] | {id, done, notes}' prd.json
tail -n +1 progress.txt
python -m unittest discover -s tests
```

