#!/usr/bin/env python

# TODO:
# 1. Concurrency control
# 2. Timeout control
# 3. Seperate infer and non-infer operations
# 4. Fix FastAPI encoding bug
# 5. Add exception handlers for a standardized error response

import logging
from typing import Optional

import fastapi
from fastapi.responses import JSONResponse
from paddlex_hps_client import triton_request
from paddlex.inference.serving.infra.models import AIStudioNoResultResponse
from paddlex.inference.serving.infra.utils import generate_log_id
from paddlex.inference.serving.schemas import paddleocr_vl as schema
from tritonclient import grpc as triton_grpc

TRITONSERVER_URL = "paddleocr-vl-tritonserver:8001"

logger = logging.getLogger(__name__)


def _configure_logger(logger: logging.Logger):
    logger.setLevel(logging.INFO)
    handler = logging.StreamHandler()
    handler.setLevel(logging.INFO)
    formatter = logging.Formatter(
        "%(asctime)s - %(funcName)s - %(levelname)s - %(message)s"
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)


_configure_logger(logger)


def _create_aistudio_output_without_result(
    error_code: str, error_msg: str, *, log_id: Optional[str] = None
) -> dict:
    resp = AIStudioNoResultResponse(
        logId=log_id if log_id is not None else generate_log_id(),
        errorCode=error_code,
        errorMsg=error_msg,
    )
    return resp.model_dump()


def _add_primary_operations(app: fastapi.FastAPI) -> None:
    def _create_handler(model_name: str):
        def _handler(request: dict):
            request_log_id = request.get("logId", generate_log_id())
            logger.info(
                "Gateway server starts processing %r request %s",
                model_name,
                request_log_id,
            )
            if "logId" in request:
                logger.warning(
                    "Duplicate 'logId' field found in %r request %s",
                    model_name,
                    request_log_id,
                )
            request["logId"] = request_log_id

            try:
                output = triton_request(
                    triton_client,
                    model_name,
                    request,
                    request_kwargs=dict(
                        timeout=600,
                        client_timeout=600,
                    ),
                )
            except triton_grpc.InferenceServerException as e:
                if e.message() == "Deadline Exceeded":
                    logger.warning(
                        "Timeout when processing %r request %s",
                        model_name,
                        request_log_id,
                    )
                    is_timedout = True
                    status_code = 504
                    output = _create_aistudio_output_without_result(
                        504,
                        "Gateway timeout",
                        log_id=request_log_id,
                    )
                    output = output.model_dump()
                else:
                    logger.error(
                        "Failed to process %r request %s due to `InferenceServerException`: %s",
                        model_name,
                        request_log_id,
                        e,
                    )
                    status_code = 500
                    output = _create_aistudio_output_without_result(
                        500,
                        "Internal server error",
                        log_id=request_log_id,
                    )
                    output = output.model_dump()
            except Exception as e:
                logger.error(
                    "Failed to process %r request %s",
                    model_name,
                    request_log_id,
                    exc_info=True,
                )
                status_code = 500
                output = _create_aistudio_output_without_result(
                    500,
                    "Internal server error",
                    log_id=request_log_id,
                )
                output = output.model_dump()
                return JSONResponse(status_code=500, content=output)
            if output["errorCode"] != 0:
                output = _create_aistudio_output_without_result(
                    output["errorCode"],
                    output["errorMsg"],
                    log_id=request_log_id,
                )
                output = output.model_dump()
            else:
                status_code = 200
            return JSONResponse(status_code=status_code, content=output)

        return _handler

    for operation_name, (endpoint, _, _) in schema.PRIMARY_OPERATIONS.items():
        # TODO: API docs
        app.post(
            endpoint,
            operation_id=operation_name,
        )(
            _create_handler(endpoint[1:]),
        )


app = fastapi.FastAPI()


@app.get(
    "/health",
    operation_id="checkHealth",
)
def check_health():
    return _create_aistudio_output_without_result(0, "Healthy")


_add_primary_operations(app)


# HACK
# https://github.com/encode/starlette/issues/864
class _EndpointFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        return record.getMessage().find("/health") == -1


logging.getLogger("uvicorn.access").addFilter(_EndpointFilter())

# HACK
triton_client: triton_grpc.InferenceServerClient = triton_grpc.InferenceServerClient(
    TRITONSERVER_URL,
    keepalive_options=triton_grpc.KeepAliveOptions(keepalive_timeout_ms=600000),
)
