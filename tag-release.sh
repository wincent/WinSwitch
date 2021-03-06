#!/bin/sh
#
# tag-release.sh script
#
# $Id$
#

### Customize this to match the desired respository:
#
REPOSITORY_NAME="WinSwitch"
#
###

PROTOCOL="http://localhost:8080"
TRUNK_PATH="svnrep/${REPOSITORY_NAME}/trunk"
TAGS_PATH="svnrep/${REPOSITORY_NAME}/tags"

echo "The current HEAD of the main trunk will be tagged."
echo "Enter a suitable tag [example: \"release-1.4\"]"
read TAG

/usr/local/bin/svn copy \
  "${PROTOCOL}/${TRUNK_PATH}" "${PROTOCOL}/${TAGS_PATH}/${TAG}" \
  -m "Tagging ${TAG} of ${REPOSITORY_NAME}"

echo "Done"
