#!/bin/sh
#
# create-branch.sh script
#
# $Id$
#

### Customize this to match the desired respository:
#
REPOSITORY_NAME="WinSwitch"
#
###

TRUNK_PATH="/usr/local/svnrep/${REPOSITORY_NAME}/trunk"
BRANCHES_PATH="/usr/local/svnrep/${REPOSITORY_NAME}/branches"

echo "The current HEAD of the main trunk will be used to create a new branch."
echo "Enter a suitable branch name [example: \"stable-1.4\"]"
read BRANCH

/usr/local/bin/svn copy \
  "file://${TRUNK_PATH}" "file://${BRANCHES_PATH}/${BRANCH}" \
  -m "Creating ${BRANCH} in ${REPOSITORY_NAME}"

echo "Done"
