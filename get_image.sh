#!/bin/bash
set -euo pipefail

url=$1
download_path="${RUNNER_TEMP}/image"
echo "download_path=${download_path}" >> "$GITHUB_ENV"
mkdir --parent "${download_path}"

image=""

if [[ ${url} = @(*.yaml|*.yml) ]]; then
    apt-get --quiet update
    apt-get --yes --quiet install yq
    wget --no-verbose --output-document="manifest.yaml" "${url}"
    echo "=== Manifest contents ==="
    cat manifest.yaml
    echo "========================="
    yq -r '.urls[] | "\(.url) \(.sha256sum)"' ./manifest.yaml > urls
    while read -r file_url sha; do
        filename="$(basename ${file_url})"
        echo "Downloading: ${filename} from ${file_url}"
        wget --no-verbose --output-document=${download_path}/${filename} ${file_url}
        echo "$sha ${download_path}/$filename" | sha256sum -c -
        [[ ${filename} = *.img.xz ]] && image="${download_path}/${filename}"
    done < urls
else 
    image="${download_path}/$(basename ${url})"
    echo "Downloading ${image} from ${url}"
    wget --no-verbose --output-document="${image}" ${url}
fi

echo "Image: ${image}"

ls -l ${download_path}

if [[ ${image} = *.xz ]]; then
    echo "Unzipping ${image}"
    unxz ${image}
    image=${image%.xz}
fi

ls -l ${download_path}

if [[ ${image} != *.img ]]; then
    echo "${image} isn't a valid image file"
    exit 1
fi

echo "image=${image}" >> "$GITHUB_OUTPUT"