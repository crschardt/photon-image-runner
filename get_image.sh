#!/bin/bash
set -euo pipefail

url=$1
download_path="${RUNNER_TEMP}/image"
mkdir --parent "${download_path}"

if [[ ${url} = @("*.yaml"|"*.yml") ]]; then
    apt-get --quiet update
    apt-get --yes --quiet install yq
    wget --no-verbose --output-document="manifest.yaml" "${url}"
    echo "=== Manifest contents ==="
    cat manifest.yaml
    echo "========================="
    yq -r '.urls[] | "\(.url) \(.sha256sum)"' manifest.yaml | while read -r url sha; do
        filename="$(basename ${url})"
        echo "Downloading: ${filename} from ${url}"
        wget --no-verbose --output-document=${download_path}/${filename} ${url}
        echo "$sha $filename" | sha256sum -c -
        [[ ${filename} = *.img.xz ]] && image="${download_path}/${filename}"
    done
else 
    image="${download_path}/$(basename ${url})"
    echo "Downloading ${image} from ${url}"
    wget --no-verbose --output-document="${image}" ${url}
fi

if [[ ${image} = *.xz ]]; then
    echo "Unzipping ${image}"
    unxz ${image}
    image=${image%.xz}
fi

echo "PWD: $(pwd)"
ls -l ${download_path}

if [[ ${image} != *.img ]]; then
    echo "${image} isn't a valid image file"
    exit 1
fi

echo "image=${image}" >> "$GITHUB_OUTPUT"