#!/bin/zsh
# Builds a Bible version package from its recipe, ready for make_release.py:
#
#     Tools/BibleImport/add_version.sh <id> [<id> ...]
#
# For each recipe Tools/BibleImport/versions/<id>.json: downloads the source
# (source_url) into Tools/BibleImport/Source/ if missing, converts it into
# Bibles/<id>/ (validating counts and reporting versification gaps against
# the KJV), embeds every verse into Bibles/<id>/embeddings.bin (int8, ~6 min
# on Apple silicon; downloads the embedding model once) and checks that the
# app's runtime embedder reproduces the index. Review the printed report,
# then run make_release.py.
set -eu
cd "$(dirname "$0")/../.."
[ $# -gt 0 ] || { echo "usage: $0 <id> [<id> ...]"; exit 2; }

LOGS=${TMPDIR:-/tmp}/openbible-add-version
DERIVED=$LOGS/DerivedData
PREFIX=dev.openbibleai.add-version
SUPPORT=~/Library/Containers/$PREFIX.OpenBibleAI/Data/Library/Application\ Support/OpenBibleAI
TEST=OpenBibleAITests/VerseIndexBuilderTests
COMMON=(-workspace OpenBibleAI.xcworkspace -scheme AllUnitTests -destination 'platform=macOS'
        -derivedDataPath $DERIVED -parallel-testing-enabled NO
        CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= BUNDLE_ID_PREFIX=$PREFIX)
mkdir -p $LOGS

for id in "$@"; do
  recipe=Tools/BibleImport/versions/$id.json
  [ -f $recipe ] || { echo "$id: no recipe at $recipe"; exit 1; }
  source=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['source'])" $recipe)
  url=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['source_url'])" $recipe)
  if [ ! -f "Tools/BibleImport/Source/$source" ]; then
    folder=Tools/BibleImport/Source/$(dirname $source)
    mkdir -p $folder
    curl -fL "$url" -o "$folder/$(basename $url)"
    (cd $folder && unzip -oq "$(basename $url)")
  fi
  echo "== $id: convert"
  python3 Tools/BibleImport/convert_vpl.py $recipe Bibles --compare Bibles/kjv/verses.json
done

Tools/generate_build_settings.sh
echo "== build tests"
xcodebuild build-for-testing $COMMON > $LOGS/build.log 2>&1 || { echo "build failed: $LOGS/build.log"; exit 1; }

for id in "$@"; do
  echo "== $id: embed ($(date +%T))"
  TEST_RUNNER_OPENBIBLE_VERSION=$id TEST_RUNNER_OPENBIBLE_BUILD_VERSE_INDEX=1 xcodebuild test-without-building $COMMON \
    "-only-testing:$TEST/buildVerseIndex()" > $LOGS/$id-embed.log 2>&1 || { echo "$id: embedding failed: $LOGS/$id-embed.log"; exit 1; }
  TEST_RUNNER_OPENBIBLE_VERSION=$id TEST_RUNNER_OPENBIBLE_EXPORT_VERSE_INDEX=1 xcodebuild test-without-building $COMMON \
    "-only-testing:$TEST/exportBundledIndex()" > $LOGS/$id-export.log 2>&1 || { echo "$id: export failed: $LOGS/$id-export.log"; exit 1; }
  cp "$SUPPORT/$id-embeddings.bin" Bibles/$id/embeddings.bin
  rm -f "$SUPPORT/$id-verse-embeddings-512.bin"
  TEST_RUNNER_OPENBIBLE_VERSION=$id TEST_RUNNER_OPENBIBLE_EVAL_RETRIEVAL=1 xcodebuild test-without-building $COMMON \
    "-only-testing:$TEST/bundledIndexMatchesRuntimeEmbedder()" > $LOGS/$id-check.log 2>&1 || { echo "$id: consistency check failed: $LOGS/$id-check.log"; exit 1; }
  echo "$id: $(grep -ho 'verses: [0-9]*' $LOGS/$id-embed.log | head -1), $(grep -ho 'worst cosine [0-9.]*' $LOGS/$id-check.log | head -1)"
  python3 -c "import json,sys; v=json.load(open(sys.argv[1])); print(f\"   {v['name']} ({v['abbreviation']}, {v['language']}): {v['copyright']}\")" Bibles/$id/version.json
  ls -l Bibles/$id | awk 'NR>1 {printf "   %-15s %12d bytes\n", $9, $5}'
done
echo "Next: python3 Tools/BibleImport/make_release.py $*"
