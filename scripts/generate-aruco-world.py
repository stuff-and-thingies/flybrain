#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from math import pi
from pathlib import Path
from textwrap import dedent

import cv2


ROOT = Path(__file__).resolve().parents[1]
SIM_DIR = ROOT / "sim"
MODELS_DIR = SIM_DIR / "models"
WORLDS_DIR = SIM_DIR / "worlds"
MAPS_DIR = SIM_DIR / "maps"

WORLD_NAME = "aruco_multi"
DICTIONARY_NAME = "DICT_4X4_50"
TAG_SIZE_M = 0.5
GROUND_SIZE_M = 30
MARKER_PX = 1024


@dataclass(frozen=True)
class Tag:
    marker_id: int
    x: float
    y: float
    z: float
    roll: float
    pitch: float
    yaw: float
    surface: str = "floor"


# Floor tags for the downward-facing camera. To add vertical tags later, add more
# entries with surface="wall" and explicit roll/pitch/yaw for the mounted plane.
TAGS = [
    Tag(0, -9.0, -6.0, 0.003, 0.0, 0.0, 0.0),
    Tag(1, -3.0, -6.0, 0.003, 0.0, 0.0, 0.0),
    Tag(2, 3.0, -6.0, 0.003, 0.0, 0.0, 0.0),
    Tag(3, 9.0, -6.0, 0.003, 0.0, 0.0, 0.0),
    Tag(4, -9.0, 0.0, 0.003, 0.0, 0.0, pi / 2.0),
    Tag(5, -3.0, 0.0, 0.003, 0.0, 0.0, pi / 2.0),
    Tag(6, 3.0, 0.0, 0.003, 0.0, 0.0, pi / 2.0),
    Tag(7, 9.0, 0.0, 0.003, 0.0, 0.0, pi / 2.0),
    Tag(8, -9.0, 6.0, 0.003, 0.0, 0.0, pi),
    Tag(9, -3.0, 6.0, 0.003, 0.0, 0.0, pi),
    Tag(10, 3.0, 6.0, 0.003, 0.0, 0.0, pi),
    Tag(11, 9.0, 6.0, 0.003, 0.0, 0.0, pi),
]


def fmt(value: float) -> str:
    if abs(value) < 1e-12:
        value = 0.0
    return f"{value:.6f}".rstrip("0").rstrip(".")


def write_model(marker_id: int, dictionary) -> None:
    model_name = f"aruco_{marker_id}"
    model_dir = MODELS_DIR / model_name
    model_dir.mkdir(parents=True, exist_ok=True)

    if hasattr(cv2.aruco, "generateImageMarker"):
        marker = cv2.aruco.generateImageMarker(dictionary, marker_id, MARKER_PX)
    else:
        marker = cv2.aruco.drawMarker(dictionary, marker_id, MARKER_PX)
    cv2.imwrite(str(model_dir / f"{model_name}.png"), marker)

    (model_dir / "model.config").write_text(
        dedent(
            f"""
            <?xml version="1.0"?>
            <model>
              <name>{model_name}</name>
              <version>1.0</version>
              <sdf version="1.9">model.sdf</sdf>
              <description>OpenCV {DICTIONARY_NAME} marker {marker_id}</description>
            </model>
            """
        ).strip()
        + "\n"
    )

    (model_dir / "model.sdf").write_text(
        dedent(
            f"""
            <?xml version="1.0" encoding="UTF-8"?>
            <sdf version="1.9">
              <model name="{model_name}">
                <static>true</static>
                <link name="base">
                  <visual name="marker_visual">
                    <geometry>
                      <plane>
                        <normal>0 0 1</normal>
                        <size>{fmt(TAG_SIZE_M)} {fmt(TAG_SIZE_M)}</size>
                      </plane>
                    </geometry>
                    <material>
                      <diffuse>1 1 1 1</diffuse>
                      <specular>0.1 0.1 0.1 1</specular>
                      <pbr>
                        <metal>
                          <albedo_map>model://{model_name}/{model_name}.png</albedo_map>
                        </metal>
                      </pbr>
                    </material>
                  </visual>
                </link>
              </model>
            </sdf>
            """
        ).strip()
        + "\n"
    )


def write_world() -> None:
    WORLDS_DIR.mkdir(parents=True, exist_ok=True)
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<sdf version="1.9">',
        f'  <world name="{WORLD_NAME}">',
        '    <physics type="ode">',
        '      <max_step_size>0.004</max_step_size>',
        '      <real_time_factor>1.0</real_time_factor>',
        '      <real_time_update_rate>250</real_time_update_rate>',
        '    </physics>',
        '    <gravity>0 0 -9.8</gravity>',
        '    <magnetic_field>6e-06 2.3e-05 -4.2e-05</magnetic_field>',
        '    <atmosphere type="adiabatic"/>',
        '    <scene>',
        '      <grid>false</grid>',
        '      <ambient>0.4 0.4 0.4 1</ambient>',
        '      <background>0.7 0.7 0.7 1</background>',
        '      <shadows>true</shadows>',
        '    </scene>',
        '',
        '    <model name="ground_plane">',
        '      <static>true</static>',
        '      <link name="link">',
        '        <collision name="collision">',
        '          <geometry>',
        '            <plane>',
        '              <normal>0 0 1</normal>',
        f'              <size>{GROUND_SIZE_M} {GROUND_SIZE_M}</size>',
        '            </plane>',
        '          </geometry>',
        '          <surface>',
        '            <friction><ode/></friction>',
        '            <bounce/>',
        '            <contact/>',
        '          </surface>',
        '        </collision>',
        '        <visual name="visual">',
        '          <geometry>',
        '            <plane>',
        '              <normal>0 0 1</normal>',
        f'              <size>{GROUND_SIZE_M} {GROUND_SIZE_M}</size>',
        '            </plane>',
        '          </geometry>',
        '          <material>',
        '            <ambient>0.8 0.8 0.8 1</ambient>',
        '            <diffuse>0.8 0.8 0.8 1</diffuse>',
        '            <specular>0.2 0.2 0.2 1</specular>',
        '          </material>',
        '        </visual>',
        '      </link>',
        '    </model>',
        '',
        '    <light name="sunUTC" type="directional">',
        '      <pose>0 0 500 0 0 0</pose>',
        '      <cast_shadows>true</cast_shadows>',
        '      <intensity>1</intensity>',
        '      <direction>0.001 0.625 -0.78</direction>',
        '      <diffuse>0.904 0.904 0.904 1</diffuse>',
        '      <specular>0.271 0.271 0.271 1</specular>',
        '      <attenuation>',
        '        <range>2000</range>',
        '        <linear>0</linear>',
        '        <constant>1</constant>',
        '        <quadratic>0</quadratic>',
        '      </attenuation>',
        '      <spot>',
        '        <inner_angle>0</inner_angle>',
        '        <outer_angle>0</outer_angle>',
        '        <falloff>0</falloff>',
        '      </spot>',
        '    </light>',
        '',
        '    <spherical_coordinates>',
        '      <surface_model>EARTH_WGS84</surface_model>',
        '      <world_frame_orientation>ENU</world_frame_orientation>',
        '      <latitude_deg>47.397971057728974</latitude_deg>',
        '      <longitude_deg>8.546163739800146</longitude_deg>',
        '      <elevation>0</elevation>',
        '    </spherical_coordinates>',
        '',
    ]

    for tag in TAGS:
        model_name = f"aruco_{tag.marker_id}"
        lines.extend(
            [
                '    <include>',
                f'      <name>{model_name}</name>',
                f'      <uri>model://{model_name}</uri>',
                f'      <pose>{fmt(tag.x)} {fmt(tag.y)} {fmt(tag.z)} {fmt(tag.roll)} {fmt(tag.pitch)} {fmt(tag.yaw)}</pose>',
                '    </include>',
                '',
            ]
        )

    lines.extend(['  </world>', '</sdf>'])
    (WORLDS_DIR / f"{WORLD_NAME}.sdf").write_text("\n".join(lines) + "\n")


def write_map() -> None:
    MAPS_DIR.mkdir(parents=True, exist_ok=True)
    lines = [
        f"world: {WORLD_NAME}",
        f"dictionary: {DICTIONARY_NAME}",
        f"tag_size_m: {fmt(TAG_SIZE_M)}",
        "frame: world",
        "tags:",
    ]

    for tag in TAGS:
        lines.extend(
            [
                f"  {tag.marker_id}:",
                f"    model: aruco_{tag.marker_id}",
                f"    surface: {tag.surface}",
                f"    position: [{fmt(tag.x)}, {fmt(tag.y)}, {fmt(tag.z)}]",
                f"    rpy: [{fmt(tag.roll)}, {fmt(tag.pitch)}, {fmt(tag.yaw)}]",
            ]
        )

    (MAPS_DIR / f"{WORLD_NAME}.yaml").write_text("\n".join(lines) + "\n")


def main() -> None:
    dictionary = cv2.aruco.getPredefinedDictionary(getattr(cv2.aruco, DICTIONARY_NAME))

    for tag in TAGS:
        write_model(tag.marker_id, dictionary)

    write_world()
    write_map()

    print(f"Generated {len(TAGS)} ArUco tags for {WORLD_NAME} in {SIM_DIR}")


if __name__ == "__main__":
    main()
