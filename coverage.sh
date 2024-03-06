set -e # Exit on error

# Generates lcov.info
forge coverage --report lcov

# Filter out test, mock, and script files
lcov \
    --rc branch_coverage=1 \
    --remove lcov.info \
    --output-file filtered-lcov.info \
    "test/*.*" "script/*.*"

# Generate summary
lcov \
    --rc branch_coverage=1 \
    --list filtered-lcov.info

# Open more granular breakdown in browser
if [ "$CI" != "true" ]
then
    genhtml \
        --rc branch_coverage=1 \
        --output-directory coverage \
        --ignore-errors category \
        filtered-lcov.info
    open coverage/index.html
fi
