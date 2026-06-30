#pragma once

#include <Eigen/Dense>

namespace imu_gnss_estimation_core
{

namespace state_index
{
static constexpr int POS_N = 0;
static constexpr int POS_E = 1;
static constexpr int POS_D = 2;
static constexpr int VEL_N = 3;
static constexpr int VEL_E = 4;
static constexpr int VEL_D = 5;

static constexpr int SIZE = 6;
};  // namespace state_index

}  // namespace imu_gnss_estimation_core
