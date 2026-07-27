#!/usr/bin/env bash

set -euo pipefail

PX4_IMAGE="${1:?PX4 image must be supplied}"
BRIDGE_IMAGE="${2:-flybrain-ros-gz-harmonic-bridge:dev}"

SIM_MODEL="${PX4_SIM_MODEL:-gz_x500_mono_cam_down}"
SIM_WORLD="${PX4_GZ_WORLD:-aruco}"
MODEL_NAME="${SIM_MODEL#gz_}"
MODEL_INSTANCE="${PX4_GZ_MODEL_NAME:-${MODEL_NAME}_0}"
GZ_PARTITION="${GZ_PARTITION:-flybrain}"

MODELS_DIR="${FLYBRAIN_PX4_GZ_MODELS:?FLYBRAIN_PX4_GZ_MODELS must be set}"
WORLDS_DIR="${FLYBRAIN_PX4_GZ_WORLDS:?FLYBRAIN_PX4_GZ_WORLDS must be set}"
WORLD_SDF="${WORLDS_DIR}/${SIM_WORLD}.sdf"
MODEL_SDF="${MODELS_DIR}/${MODEL_NAME}/model.sdf"

export GZ_SIM_RESOURCE_PATH="${MODELS_DIR}:${WORLDS_DIR}${GZ_SIM_RESOURCE_PATH:+:${GZ_SIM_RESOURCE_PATH}}"
export GZ_PARTITION

if [[ -z "${GZ_SIM_SERVER_CONFIG_PATH:-}" ]]; then
    SERVER_CONFIG="${FLYBRAIN_PX4_GZ_SERVER_CONFIG:-}"

    if [[ -n "${SERVER_CONFIG}" && -f "${SERVER_CONFIG}" ]]; then
        export GZ_SIM_SERVER_CONFIG_PATH="${SERVER_CONFIG}"
    fi
fi

PX4_CONTAINER="flybrain-px4-gz"
BRIDGE_CONTAINER="flybrain-gz-bridge"

GZ_PID=""
XRCE_PID=""
FOXGLOVE_PID=""

GZ_LOG="/tmp/flybrain-host-gz.log"
PX4_LOG="/tmp/flybrain-px4-gz.log"
BRIDGE_LOG="/tmp/flybrain-gz-bridge.log"
XRCE_LOG="/tmp/flybrain-xrce.log"
FOXGLOVE_LOG="/tmp/flybrain-foxglove.log"

run_gz() {
    ${FLYBRAIN_GZ_CMD:-nixGL gz} "$@"
}

dump_container_logs() {
    local container="$1"
    local log_file="$2"

    if docker inspect "${container}" >/dev/null 2>&1; then
        docker logs "${container}" >"${log_file}" 2>&1 || true
    fi
}

cleanup() {
    trap - EXIT INT TERM

    echo
    echo "Stopping FlyBrain host-Gazebo simulation..."

    if [[ -n "${XRCE_PID}" ]]; then
        kill "${XRCE_PID}" 2>/dev/null || true
    fi

    if [[ -n "${FOXGLOVE_PID}" ]]; then
        kill "${FOXGLOVE_PID}" 2>/dev/null || true
    fi

    dump_container_logs "${BRIDGE_CONTAINER}" "${BRIDGE_LOG}"
    dump_container_logs "${PX4_CONTAINER}" "${PX4_LOG}"

    docker stop "${BRIDGE_CONTAINER}" >/dev/null 2>&1 || true
    docker stop "${PX4_CONTAINER}" >/dev/null 2>&1 || true

    if [[ -n "${GZ_PID}" ]]; then
        kill "${GZ_PID}" 2>/dev/null || true
        wait "${GZ_PID}" 2>/dev/null || true
    fi

    echo "Logs:"
    echo "  Host Gazebo:   ${GZ_LOG}"
    echo "  PX4/Gazebo:    ${PX4_LOG}"
    echo "  Camera bridge: ${BRIDGE_LOG}"
    echo "  XRCE:          ${XRCE_LOG}"
    echo "  Foxglove:      ${FOXGLOVE_LOG}"
    echo
    echo "Simulation stopped."
}

trap cleanup EXIT INT TERM

if [[ ! -f "${WORLD_SDF}" ]]; then
    echo "World file not found: ${WORLD_SDF}" >&2
    exit 1
fi

if [[ ! -f "${MODEL_SDF}" ]]; then
    echo "Model file not found: ${MODEL_SDF}" >&2
    exit 1
fi

docker rm -f "${BRIDGE_CONTAINER}" >/dev/null 2>&1 || true
docker rm -f "${PX4_CONTAINER}" >/dev/null 2>&1 || true
rm -f "${GZ_LOG}" "${PX4_LOG}" "${BRIDGE_LOG}" "${XRCE_LOG}" "${FOXGLOVE_LOG}"

echo "[1/5] Starting host Gazebo..."

if [[ "${FLYBRAIN_GZ_GUI:-1}" == "1" ]]; then
    run_gz sim -r "${WORLD_SDF}" >"${GZ_LOG}" 2>&1 &
else
    run_gz sim -r -s "${WORLD_SDF}" >"${GZ_LOG}" 2>&1 &
fi

GZ_PID=$!

echo "      Waiting for Gazebo world..."

GZ_READY=""

for _ in {1..160}; do
    if run_gz topic -l 2>/dev/null | grep -q "/world/${SIM_WORLD}/"; then
        GZ_READY=1
        break
    fi

    if ! kill -0 "${GZ_PID}" 2>/dev/null; then
        echo "Host Gazebo exited during startup."
        echo "Host Gazebo log: ${GZ_LOG}"
        exit 1
    fi

    sleep 0.25
done

if [[ -z "${GZ_READY}" ]]; then
    echo "Timed out waiting for host Gazebo world topics."
    echo "Host Gazebo log: ${GZ_LOG}"
    exit 1
fi

echo "[2/5] Spawning ${MODEL_INSTANCE} into ${SIM_WORLD}..."

sdf_str="<sdf version=\"1.6\"> <include> <uri>file://${MODEL_SDF}</uri> </include> </sdf>"

run_gz service \
    -s "/world/${SIM_WORLD}/create" \
    --reqtype gz.msgs.EntityFactory \
    --reptype gz.msgs.Boolean \
    --timeout 5000 \
    --req "name: \"${MODEL_INSTANCE}\", allow_renaming: false, sdf: '${sdf_str}'" \
    >/dev/null

sleep 1

echo "[3/5] Starting standalone PX4..."

docker run -dt \
    --name "${PX4_CONTAINER}" \
    --network host \
    --cap-add SYS_NICE \
    --ulimit rtprio=99 \
    --ulimit memlock=-1 \
    -e PX4_GZ_STANDALONE=1 \
    -e GZ_PARTITION="${GZ_PARTITION}" \
    -e PX4_GZ_WORLD="${SIM_WORLD}" \
    -e PX4_GZ_MODEL_NAME="${MODEL_INSTANCE}" \
    -e PX4_SIM_MODEL="${SIM_MODEL}" \
    "${PX4_IMAGE}" \
    >/dev/null

echo "      Waiting for PX4 startup..."

PX4_READY=""

for _ in {1..120}; do
    if docker logs "${PX4_CONTAINER}" 2>&1 | grep -q 'Startup script returned successfully'; then
        PX4_READY=1
        break
    fi

    px4_running="$(docker inspect -f '{{.State.Running}}' "${PX4_CONTAINER}" 2>/dev/null || true)"

    if [[ "${px4_running}" != "true" ]]; then
        echo "PX4 container exited during startup."
        dump_container_logs "${PX4_CONTAINER}" "${PX4_LOG}"
        echo "PX4 log: ${PX4_LOG}"
        exit 1
    fi

    sleep 0.25
done

if [[ -z "${PX4_READY}" ]]; then
    echo "Timed out waiting for PX4 startup."
    dump_container_logs "${PX4_CONTAINER}" "${PX4_LOG}"
    echo "PX4 log: ${PX4_LOG}"
    exit 1
fi

echo "[4/5] Starting Gazebo camera bridge..."

docker run -d \
    --name "${BRIDGE_CONTAINER}" \
    --network host \
    -e GZ_PARTITION="${GZ_PARTITION}" \
    "${BRIDGE_IMAGE}" \
    bash -lc '
        source /opt/ros/jazzy/setup.bash
        exec ros2 run ros_gz_bridge parameter_bridge \
            --ros-args \
            -p config_file:=/flybrain/gz_bridge.yaml
    ' \
    >/dev/null

echo "[5/5] Starting Micro-XRCE-DDS Agent and Foxglove bridge..."

MicroXRCEAgent udp4 -p 8888 \
    >"${XRCE_LOG}" 2>&1 &

XRCE_PID=$!

ros2 launch foxglove_bridge foxglove_bridge_launch.xml \
    >"${FOXGLOVE_LOG}" 2>&1 &

FOXGLOVE_PID=$!

echo
echo "FlyBrain host-Gazebo simulation is running."
echo
echo "  Host Gazebo:   pid ${GZ_PID}"
echo "  PX4:           ${PX4_CONTAINER}"
echo "  Camera bridge: ${BRIDGE_CONTAINER}"
echo "  Model:         ${SIM_MODEL}"
echo "  Gazebo model:  ${MODEL_INSTANCE}"
echo "  World:         ${SIM_WORLD}"
echo "  GZ partition:  ${GZ_PARTITION}"
echo "  Host Gazebo log: ${GZ_LOG}"
echo "  PX4 log:         ${PX4_LOG}"
echo "  Bridge log:      ${BRIDGE_LOG}"
echo "  XRCE log:        ${XRCE_LOG}"
echo "  Foxglove log:    ${FOXGLOVE_LOG}"
echo
echo "Run QGroundControl separately with:"
echo "  qcntrl"
echo
echo "Press Ctrl-C here to stop the whole simulation stack."
echo

PX4_EXIT_CODE="$(docker wait "${PX4_CONTAINER}")"
dump_container_logs "${PX4_CONTAINER}" "${PX4_LOG}"

echo "PX4 exited with code ${PX4_EXIT_CODE}."
echo "PX4 log: ${PX4_LOG}"
