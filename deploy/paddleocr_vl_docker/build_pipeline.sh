#!/usr/bin/env bash

build_for_offline='false'
paddleocr_version='3.3.2'
paddlex_version='3.3.13'

while [[ $# -gt 0 ]]; do
    case $1 in
        --device-type)
            [ -z "$2" ] && {
                echo "`--device-type` requires a value" >&2
                exit 2
            }
            device_type="$2"
            shift
            shift
            case "${device_type}" in
                gpu|sm120|dcu|xpu|metax|iluvatar|npu)
                    ;;
                *)
                    echo "Unknown device type: ${device_type}" >&2
                    exit 2
                    ;;
            esac
            ;;
        --offline)
            build_for_offline='true'
            shift
            ;;
        --ppocr-version)
            [ -z "$2" ] && {
                echo "`--ppocr-version` requires a value" >&2
                exit 2
            }
            paddleocr_version="$2"
            shift
            shift
            ;;
        --paddlex-version)
            [ -z "$2" ] && {
                echo "`--paddlex-version` requires a value" >&2
                exit 2
            }
            paddlex_version="$2"
            shift
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

tag_suffix="latest-${device_type}"

if [ "${build_for_offline}" = 'true' ]; then
    tag_suffix="${tag_suffix}-offline"
fi

dockerfile="accelerators/${device_type}/pipeline.Dockerfile"
dockerfile_hash="$(sha256sum "${dockerfile}" | cut -c1-12)"

docker build \
    -f "${dockerfile}" \
    -t "ccr-2vdh3abv-pub.cnc.bj.baidubce.com/paddlepaddle/paddleocr-vl:${tag_suffix}" \
    --build-arg BUILD_FOR_OFFLINE="${build_for_offline}" \
    --build-arg PADDLEOCR_VERSION="==${paddleocr_version}" \
    --build-arg PADDLEX_VERSION="==${paddlex_version}" \
    --build-arg http_proxy="${http_proxy}" \
    --build-arg https_proxy="${https_proxy}" \
    --build-arg no_proxy="${no_proxy}" \
    --label org.opencontainers.image.version.paddleocr="${paddleocr_version}" \
    --label org.opencontainers.image.version.paddlex="${paddlex_version}" \
    --label org.opencontainers.image.version.dockerfile.sha="${dockerfile_hash}" \
    .

image_version="${paddleocr_version}-${paddlex_version}-${dockerfile_hash}"
docker tag "ccr-2vdh3abv-pub.cnc.bj.baidubce.com/paddlepaddle/paddleocr-vl:${tag_suffix}" "ccr-2vdh3abv-pub.cnc.bj.baidubce.com/paddlepaddle/paddleocr-vl:${tag_suffix/latest/${image_version}}"
