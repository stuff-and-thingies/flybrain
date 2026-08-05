FROM ros:jazzy-ros-base

RUN apt-get update && \
    apt-get install -y \
        ros-jazzy-ros-gz-bridge \
        ros-jazzy-rosgraph-msgs \
        ros-jazzy-sensor-msgs \
        ros-jazzy-tf2-msgs && \
    rm -rf /var/lib/apt/lists/*

COPY config/gz_bridge.yaml /flybrain/gz_bridge.yaml
