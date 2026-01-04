#!/bin/bash
set -euxo pipefail
shopt -s extglob

url=$1
download_path="${RUNNER_TEMP}/image"
echo "download_path=${download_path}" >> "$GITHUB_ENV"
mkdir --parent "${download_path}"

image=""

case ${url} in
    file://* )
        echo "Using local file as image: ${url}"
        image="${url#file://}"
    ;;
    http?(s)://*.yam?(l) )
        apt-get --quiet update
        apt-get --yes --quiet install yq
        echo "Downloading manifest from ${url}"
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
    ;;
    http?(s)://* )
        image="${download_path}/$(basename ${url})"
        echo "Downloading ${image} from ${url}"
        wget --no-verbose --output-document="${image}" ${url}
    ;;
    * )
        echo "Unrecognized image source ${url}. Exiting!"
        exit 1
    ;;
esac

echo "Image: ${image}"
ls -la ${download_path}

if [[ ${image} = *.xz ]]; then
    echo "Unzipping ${image}"
    unxz ${image}
    image=${image%.xz}
fi

if [[ ${image} = *.tar ]]; then
    echo "Untarring ${image}"
    tar -xf ${image}
    rm ${image}
    image=$(find . -type f \( -name '*.img' \) -exec ls -s {} + 2>/dev/null | sort -rn | head -n1 | awk '{print $2}')
fi

echo "Image: ${image}"
ls -la $(dirname ${image})

if [[ ${image} != *.img ]]; then
    echo "${image} isn't a valid image file"
    exit 1
fi

echo "image=${image}" >> "$GITHUB_OUTPUT"