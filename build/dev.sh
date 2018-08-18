#!/usr/bin/env bash
#
# Set up a development build of Oil on CPython.
# This is in constrast to the release build, which bundles Oil with "OVM" (a
# slight fork of CPython).

# Build Python extension modules.  We use symlinks instead of installing them
# globally (or using virtualenv).
#
# Usage:
#   ./pybuild.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

source test/common.sh  # R_PATH

# In some distros, 'python' is python3, which confuses first-time developers.
# https://github.com/oilshell/oil/issues/97
readonly PYTHON_VERSION="$(python --version 2>&1)"

# bash weirdness: VERSION_REGEX must NOT be inline in the expression, and must
# NOT be quoted.
readonly VERSION_REGEX='Python (2\.7\.[0-9]+)'

if [[ "${PYTHON_VERSION}" =~ $VERSION_REGEX ]]; then
  true
else
  echo >&2 'FATAL: Oil dev requires Python 2.7.*'
  echo >&2 "But you have '${PYTHON_VERSION}'"
  echo >&2 'Hint: Use virtualenv to create a Python 2.7 environment.'
  exit 1
fi

ubuntu-deps() {
  # python-dev: for pylibc
  # gawk: used by spec-runner.sh for the special match() function.
  # time: used to collect the exit code and timing of a test
  # libreadline-dev: needed for the build/prepare.sh Python build.
  sudo apt install python-dev gawk time libreadline-dev

  test/spec.sh install-shells

}

# Needed for the release process, but not the dev process.
release-ubuntu-deps() {
  # For the release to run test/report.R, you need r-base-core too.
  # cloc is used for line counts
  # TODO: switch to CommonMark rather than using markdown.pl.
  sudo apt install r-base-core cloc markdown
}

r-packages() {
  # Install to a directory that doesn't require root.  This requires setting
  # R_LIBS_USER.  Or library(dplyr, lib.loc = "~/R", but the former is preferable.
  mkdir -p ~/R
  INSTALL_DEST=$R_PATH Rscript -e 'install.packages(c("dplyr", "tidyr", "stringr"), lib=Sys.getenv("INSTALL_DEST"), repos="http://cran.us.r-project.org")'
}

test-r-packages() {
  R_LIBS_USER=$R_PATH Rscript -e 'library(dplyr)'
}

# Produces _devbuild/gen/osh_help.py
gen-help() {
  build/doc.sh osh-quick-ref
}

# TODO:
# import pickle
# The import should be replaced with 
# f = util.GetResourceLoader().open('_devbuild/osh_asdl.pickle')
# TYPE_LOOKUP = pickle.load(f)
gen-types-asdl() {
  local out=_devbuild/gen/types_asdl.py
  local import='from osh.meta import TYPES_TYPE_LOOKUP as TYPE_LOOKUP'
  PYTHONPATH=. osh/asdl_gen.py py \
    osh/types.asdl "$import" _devbuild/types_asdl.pickle > $out
  echo "Wrote $out"
}

gen-osh-asdl() {
  local out=_devbuild/gen/osh_asdl.py
  local import='from osh.meta import OSH_TYPE_LOOKUP as TYPE_LOOKUP'
  PYTHONPATH=. osh/asdl_gen.py py \
    osh/osh.asdl "$import" _devbuild/osh_asdl.pickle > $out
  echo "Wrote $out"
}

gen-runtime-asdl() {
  local out=_devbuild/gen/runtime_asdl.py
  local import='from osh.meta import RUNTIME_TYPE_LOOKUP as TYPE_LOOKUP'
  PYTHONPATH=. osh/asdl_gen.py py \
    core/runtime.asdl "$import" _devbuild/runtime_asdl.pickle > $out
  echo "Wrote $out"
}

# TODO: should fastlex.c be part of the dev build?  It means you need re2c
# installed?  I don't think it makes sense to have 3 builds, so yes I think we
# can put it here for simplicity.
# However one problem is that if the Python lexer definition is changed, then
# you need to run re2c again!  I guess you should just provide a script to
# download it.

py-ext() {
  local name=$1
  local setup_script=$2

  mkdir -p _devbuild/py-ext
  local arch=$(uname -m)
  $setup_script build --build-lib _devbuild/py-ext/$arch

  shopt -s failglob
  local so=$(echo _devbuild/py-ext/$arch/$name.so)
  ln -s -f -v $so $name.so

  file $name.so
}

pylibc() {
  py-ext libc build/setup.py
  PYTHONPATH=. native/libc_test.py "$@"
}

fastlex() {
  build/codegen.sh ast-id-lex

  # Why do we need this?  It gets stail otherwise.
  rm -f _devbuild/py-ext/x86_64/fastlex.so

  py-ext fastlex build/setup_fastlex.py
  PYTHONPATH=. native/fastlex_test.py
}

clean() {
  rm -f --verbose libc.so fastlex.so
  rm -r -f --verbose _devbuild/py-ext
}

# No fastlex, because we don't want to require re2c installation.
minimal() {
  mkdir -p _devbuild/gen
  # so osh_help.py and osh_asdl.py are importable
  touch _devbuild/__init__.py  _devbuild/gen/__init__.py

  gen-help
  gen-types-asdl
  gen-osh-asdl
  gen-runtime-asdl
  pylibc
}

# Prerequisites: build/codegen.sh {download,install}-re2c
all() {
  minimal
  build/codegen.sh
  fastlex
}

"$@"
