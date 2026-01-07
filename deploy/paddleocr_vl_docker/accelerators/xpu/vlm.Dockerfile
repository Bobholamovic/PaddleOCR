# TODO: Allow regular users

ARG BACKEND=fastdeploy


FROM ccr-2vdh3abv-pub.cnc.bj.baidubce.com/paddlepaddle/fastdeploy-xpu:2.3.0 AS base-fastdeploy


FROM base-${BACKEND}

RUN python -m pip install https://paddle-model-ecology.bj.bcebos.com/paddlex/PaddleX3.0/deploy/hardware/whl/fastdeploy_xpu-2.3.0.dev0-py3-none-any.whl \
    && python -m pip install https://paddle-model-ecology.bj.bcebos.com/paddlex/PaddleX3.0/deploy/hardware/whl/paddlepaddle_xpu-0.0.0-cp310-cp310-linux_x86_64.whl

ARG PADDLEOCR_VERSION=">=3.3.2,<3.4"
ARG PADDLEX_VERSION=">=3.3.12,<3.4"
RUN python -m pip install "paddleocr[doc-parser]${PADDLEOCR_VERSION}" "paddlex[serving]${PADDLEX_VERSION}"

RUN groupadd -g 1000 paddleocr \
    && useradd -m -s /bin/bash -u 1000 -g 1000 paddleocr
ENV HOME=/home/paddleocr
WORKDIR /home/paddleocr

USER paddleocr

ARG BUILD_FOR_OFFLINE=false
RUN if [ "${BUILD_FOR_OFFLINE}" = 'true' ]; then \
        mkdir -p "${HOME}/.paddlex/official_models" \
        && cd "${HOME}/.paddlex/official_models" \
        && wget https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PaddleOCR-VL_infer.tar \
        && tar -xf PaddleOCR-VL_infer.tar \
        && mv PaddleOCR-VL_infer PaddleOCR-VL \
        && rm -f PaddleOCR-VL_infer.tar; \
    fi

ARG BACKEND
ENV BACKEND=${BACKEND}
CMD ["/bin/bash", "-c", "paddleocr genai_server --model_name PaddleOCR-VL-0.9B --host 0.0.0.0 --port 8080 --backend ${BACKEND}"]
