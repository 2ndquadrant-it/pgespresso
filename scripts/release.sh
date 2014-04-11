#!/bin/sh

# Copyright (C) 2011-2014 2ndQuadrant Italia (Devise.IT S.r.L.)
#
# This file is part of pgespresso.
#
# See COPYING for licensing information

set -e

BASE="$(dirname $(cd $(dirname "$0"); pwd))"
cd "$BASE"

VERSION="$(awk -F "[[:space:]=']+" '/default_version/{print $2}' pgespresso.control)"
scripts/gitlog-to-changelog > ChangeLog
git add ChangeLog
git commit -m "Update the ChangeLog file"
scripts/gitlog-to-changelog > ChangeLog
git add ChangeLog
git commit -m "Update the ChangeLog file" --amend
if ! git tag -s -m "Release ${VERSION}" ${VERSION}
then
  echo "Cannot tag the release as the private key is missing"
fi
