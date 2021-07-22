#!/usr/bin/env bash

# Copyright 2020 The Magma Authors.

# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# promote.sh copies specified artifacts from one repo to another.

set -e -o pipefail

promote_image () {
  ORIGIN_REPO="$1"
  DEST_REPO="$2"
  IMAGE="$3"

  curl --request POST --user "$ARTIFACTORY_USERNAME":"$ARTIFACTORY_TOKEN" --fail \
   "$DOCKER_ARTIFACTORY_API_URL/$ORIGIN_REPO/v2/promote" \
   -H "Content-Type: application/json" -d {"targetRepo":"$DEST_REPO","dockerRepository":"$IMAGE","tag": "$TAG","copy": "true" }
}

get_image () {
  ARTIFACT="$1"
  curl --output /dev/null --silent  --write-out "%{http_code}" \
   "$DOCKER_ARTIFACTORY_URL/$ORIGIN_REPO/$IMAGE" || :
}

usage() {
  echo "Supply at least one artifact to promote: $0 ARTIFACT_PATH"
  exit 2
}

exitmsg() {
  echo "$1"
  exit 1
}


# Parse the args
while [[ $# -gt 0 ]]
do
key="$1"
case $key in
    -r|--repos)
    REPOS="$2"
    shift  # pass argument or value
    ;;
    -i|--input-tag)
    CI_TAG="$2"
    shift
    ;;
    -p|--production-tag)
    PRODUCTION_TAG="$2"
    shift
    ;;
    -tl|--tag-latest)
    TAG_LATEST="$2"
    shift
    ;;
    -h|--help)
    usage
    shift
    ;;
    *)
    echo "Error: unknown cmdline option: $key"
    usage
    ;;
esac
shift  # past argument or value
done

# Check if the required args and env-vars present
[ $# -eq 0 ] && usage

# Define default values
DOCKER_ARTIFACTORY_URL="${HELM_CHART_ARTIFACTORY_URL:-https://artifactory.magmacore.org:443/artifactory}"

if [[ -z $ARTIFACTORY_USERNAME ]]; then
  exitmsg "Environment variable ARTIFACTORY_USERNAME must be set"
fi

if [[ -z $ARTIFACTORY_TOKEN ]]; then
  exitmsg "Environment variable ARTIFACTORY_TOKEN must be set"
fi

# Trim last backslash if exists
# shellcheck disable=SC2001
DOCKER_ARTIFACTORY_URL="$(echo "$DOCKER_ARTIFACTORY_URL" | sed 's:/$::')"

# shellcheck disable=SC2207
# Docker images does not contains special characters so we can skip the check
REPO_ARRAY=($(echo "$REPOS" | tr "|" "\n"))

# Verify existence of the docker repo
RESPONSE_CODE_REPO="$(curl --output /dev/null --stderr /dev/null --silent --write-out "%{http_code}"  "$DOCKER_ARTIFACTORY_URL/$HELM_CHART_MUSEUM_ORIGIN_REPO/" || :)"
if [ "$RESPONSE_CODE_REPO" != "200" ]; then
  exitmsg "There was an error connecting to the artifactory repository $HELM_CHART_MUSEUM_ORIGIN_REPO, the http error code was $RESPONSE_CODE_REPO"
fi

# Form API URL
HELM_CHART_MUSEUM_API_URL="$HELM_CHART_ARTIFACTORY_URL/api/docker"

# iterate through artifacts to promote
for artifact in "$@"
do
    RESPONSE_CODE_ARTIFACT="$(get_artifact "$artifact")"
    if [ "$RESPONSE_CODE_ARTIFACT" == "200" ]; then
      promote_artifact "$artifact"
    elif [ "$RESPONSE_CODE_ARTIFACT" == "404" ]; then
      exitmsg "The artifact $artifact was not found in repository $HELM_CHART_MUSEUM_ORIGIN_REPO"
    else
      exitmsg "There was an error retrieving $artifact from repository $HELM_CHART_MUSEUM_ORIGIN_REPO, the http error code was $RESPONSE_CODE_ARTIFACT"
    fi
done

printf '\n'
echo "Promoted Orc8r chart artifacts $* from $HELM_CHART_MUSEUM_ORIGIN_REPO to $HELM_CHART_MUSEUM_DEST_REPO successfully."
