#!/bin/sh
# prek/pre-commit hook: fail if any of the given Go files is not gofmt-formatted
out="$(gofmt -l "$@")"
[ -z "$out" ] || { echo "gofmt needed:"; echo "$out"; exit 1; }
