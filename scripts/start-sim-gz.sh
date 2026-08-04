#!/usr/bin/env bash

set -euo pipefail

PX4_IMAGE="${1:?PX4 image must be supplied}"
BRIDGE_IMAGE="${2:-flybrain-ros-gz-harmonic-bridge:dev}"

SIM_MODEL="${PX4_SIM_MODEL:-gz_x500_mono_cam_down}"
SIM_WORLD="${PX4_GZ_WORLD:-aruco}"
MODEL_NAME="${SIM_MODEL#gz_}"
MODEL_INSTANCE="${PX4_GZ_MODEL_NAME:-${MODEL_NAME}_0}"
GZ_PARTITION="${GZ_PARTITION:-flybrain}"

ORIG_MODELS_DIR="${FLYBRAIN_PX4_GZ_MODELS:?FLYBRAIN_PX4_GZ_MODELS must be set}"
ORIG_WORLDS_DIR="${FLYBRAIN_PX4_GZ_WORLDS:?FLYBRAIN_PX4_GZ_WORLDS must be set}"
MODELS_DIR="${ORIG_MODELS_DIR}"
WORLDS_DIR="${ORIG_WORLDS_DIR}"
WORLD_SDF="${WORLDS_DIR}/${SIM_WORLD}.sdf"
MODEL_SDF="${MODELS_DIR}/${MODEL_NAME}/model.sdf"
LITE_DIR=""

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

GZ_LOG="/tmp/flybrain-gazebo.log"
PX4_LOG="/tmp/flybrain-px4-gz.log"
BRIDGE_LOG="/tmp/flybrain-gz-bridge.log"
XRCE_LOG="/tmp/flybrain-xrce.log"
FOXGLOVE_LOG="/tmp/flybrain-foxglove.log"
GZ_RENDER_ARGS=(
    --render-engine-server-api-backend "${FLYBRAIN_GZ_RENDER_SERVER_BACKEND:-opengl}"
    --render-engine-gui-api-backend "${FLYBRAIN_GZ_RENDER_GUI_BACKEND:-opengl}"
)

prepare_lite_resources() {
    LITE_DIR="$(mktemp -d /tmp/flybrain-gz-lite.XXXXXX)"

    mkdir -p "${LITE_DIR}/models" "${LITE_DIR}/worlds"
    cp -a "${ORIG_MODELS_DIR}/mono_cam" "${LITE_DIR}/models/"
    cp -a "${ORIG_MODELS_DIR}/${MODEL_NAME}" "${LITE_DIR}/models/"
    cp -a "${ORIG_WORLDS_DIR}/${SIM_WORLD}.sdf" "${LITE_DIR}/worlds/"
    chmod -R u+w "${LITE_DIR}"

    perl -0pi -e 's|<width>1280</width>|<width>640</width>|g; s|<height>960</height>|<height>480</height>|g; s|<update_rate>30</update_rate>|<update_rate>10</update_rate>|g; s|<visualize>true</visualize>|<visualize>false</visualize>|g' \
        "${LITE_DIR}/models/mono_cam/model.sdf"
    perl -0pi -e 's|<shadows>true</shadows>|<shadows>false</shadows>|g' \
        "${LITE_DIR}/worlds/${SIM_WORLD}.sdf"

    if ! grep -q '<update_rate>10</update_rate>' "${LITE_DIR}/models/mono_cam/model.sdf"; then
        echo "Failed to prepare lightweight mono_cam model." >&2
        exit 1
    fi

    MODELS_DIR="${LITE_DIR}/models"
    WORLDS_DIR="${LITE_DIR}/worlds"
    WORLD_SDF="${WORLDS_DIR}/${SIM_WORLD}.sdf"
    MODEL_SDF="${MODELS_DIR}/${MODEL_NAME}/model.sdf"
    export GZ_SIM_RESOURCE_PATH="${MODELS_DIR}:${WORLDS_DIR}:${ORIG_MODELS_DIR}:${ORIG_WORLDS_DIR}${GZ_SIM_RESOURCE_PATH:+:${GZ_SIM_RESOURCE_PATH}}"
}

run_gz() {
    if [[ "${FLYBRAIN_GZ_NATIVE:-0}" == "1" ]]; then
        if [[ ! -f /opt/ros/jazzy/setup.bash ]]; then
            echo "Native Gazebo requested, but /opt/ros/jazzy/setup.bash was not found." >&2
            exit 1
        fi

        local resource_path="${GZ_SIM_RESOURCE_PATH}"
        local server_config="${GZ_SIM_SERVER_CONFIG_PATH:-}"
        local partition="${GZ_PARTITION}"

        env -i \
            HOME="${HOME:-}" \
            USER="${USER:-}" \
            LOGNAME="${LOGNAME:-${USER:-}}" \
            DISPLAY="${DISPLAY:-}" \
            XAUTHORITY="${XAUTHORITY:-}" \
            XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
            DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" \
            WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
            PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            FLYBRAIN_NATIVE_GZ_RESOURCE_PATH="${resource_path}" \
            FLYBRAIN_NATIVE_GZ_SERVER_CONFIG="${server_config}" \
            FLYBRAIN_NATIVE_GZ_PARTITION="${partition}" \
            bash -lc '
            source /opt/ros/jazzy/setup.bash
            export GZ_SIM_RESOURCE_PATH="${FLYBRAIN_NATIVE_GZ_RESOURCE_PATH}${GZ_SIM_RESOURCE_PATH:+:${GZ_SIM_RESOURCE_PATH}}"
            export GZ_SIM_SERVER_CONFIG_PATH="${FLYBRAIN_NATIVE_GZ_SERVER_CONFIG}"
            export GZ_PARTITION="${FLYBRAIN_NATIVE_GZ_PARTITION}"
            exec gz "$@"
        ' bash "$@"
        return
    fi

    ${FLYBRAIN_GZ_CMD:-nixGL gz} "$@"
}

if ! command -v docker >/dev/null 2>&1; then
    echo "docker not found. Install Docker and enter the devshell again." >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon unavailable or current user cannot access it." >&2
    echo "Start Docker, or add your user to the docker group and log in again." >&2
    exit 1
fi

if ! command -v MicroXRCEAgent >/dev/null 2>&1; then
    echo "MicroXRCEAgent not found. Run this from 'nix develop --impure'." >&2
    exit 1
fi

if ! command -v ros2 >/dev/null 2>&1; then
    echo "ros2 not found. Run this from 'nix develop --impure'." >&2
    exit 1
fi

if ! docker image inspect "${PX4_IMAGE}" >/dev/null 2>&1; then
    echo "PX4 image not loaded in Docker: ${PX4_IMAGE}" >&2
    echo "Use the devshell start-sim-gz-nix or start-sim-gz-native function so it can load the image automatically." >&2
    exit 1
fi

if ! docker image inspect "${BRIDGE_IMAGE}" >/dev/null 2>&1; then
    echo "Gazebo bridge image not found in Docker: ${BRIDGE_IMAGE}" >&2
    echo "Run build-gz-bridge, or use the devshell start-sim-gz-nix or start-sim-gz-native function." >&2
    exit 1
fi

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
    echo "Stopping FlyBrain Gazebo simulation..."

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

    if [[ -n "${LITE_DIR}" ]]; then
        rm -rf "${LITE_DIR}"
    fi

    echo "Logs:"
    echo "  Gazebo:        ${GZ_LOG}"
    echo "  PX4/Gazebo:    ${PX4_LOG}"
    echo "  Camera bridge: ${BRIDGE_LOG}"
    echo "  XRCE:          ${XRCE_LOG}"
    echo "  Foxglove:      ${FOXGLOVE_LOG}"
    echo
    echo "Simulation stopped."
}

trap cleanup EXIT INT TERM

if [[ "${FLYBRAIN_GZ_LITE:-0}" == "1" ]]; then
    prepare_lite_resources
fi

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

echo "[1/5] Starting Gazebo..."

if [[ "${FLYBRAIN_GZ_GUI:-1}" == "1" ]]; then
    run_gz sim -r "${GZ_RENDER_ARGS[@]}" "${WORLD_SDF}" >"${GZ_LOG}" 2>&1 &
else
    run_gz sim -r -s "${GZ_RENDER_ARGS[@]}" "${WORLD_SDF}" >"${GZ_LOG}" 2>&1 &
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
        echo "Gazebo exited during startup."
        echo "Gazebo log: ${GZ_LOG}"
        exit 1
    fi

    sleep 0.25
done

if [[ -z "${GZ_READY}" ]]; then
    echo "Timed out waiting for Gazebo world topics."
    echo "Gazebo log: ${GZ_LOG}"
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
    -e PX4_GZ_WORLD="${SIM_WORLD}" \
    "${BRIDGE_IMAGE}" \
    bash -lc '
        source /opt/ros/jazzy/setup.bash
        sed "s|/world/aruco/|/world/${PX4_GZ_WORLD}/|g" \
            /flybrain/gz_bridge.yaml > /tmp/flybrain_gz_bridge.yaml
        exec ros2 run ros_gz_bridge parameter_bridge \
            --ros-args \
            -p config_file:=/tmp/flybrain_gz_bridge.yaml
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
echo "FlyBrain Gazebo simulation is running."
echo
echo "  Gazebo:        pid ${GZ_PID}"
echo "  PX4:           ${PX4_CONTAINER}"
echo "  Camera bridge: ${BRIDGE_CONTAINER}"
echo "  Model:         ${SIM_MODEL}"
echo "  Gazebo model:  ${MODEL_INSTANCE}"
echo "  World:         ${SIM_WORLD}"
echo "  GZ partition:  ${GZ_PARTITION}"
echo "  Lite mode:     ${FLYBRAIN_GZ_LITE:-0}"
echo "  Native Gazebo: ${FLYBRAIN_GZ_NATIVE:-0}"
if [[ "${FLYBRAIN_GZ_NATIVE:-0}" == "1" ]]; then
    echo "  Gazebo cmd:    /opt/ros/jazzy Gazebo"
else
    echo "  Gazebo cmd:    ${FLYBRAIN_GZ_CMD:-nixGL gz}"
fi
echo "  Render backend: server=${FLYBRAIN_GZ_RENDER_SERVER_BACKEND:-opengl}, gui=${FLYBRAIN_GZ_RENDER_GUI_BACKEND:-opengl}"
echo "  Gazebo log:      ${GZ_LOG}"
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
