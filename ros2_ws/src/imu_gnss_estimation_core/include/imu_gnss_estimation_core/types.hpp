#pragma once

#include <Eigen/Dense>

#include "imu_gnss_estimation_core/state.hpp"

namespace imu_gnss_estimation_core
{

using StateVec = Eigen::Matrix<double, StateIndex::SIZE, 1>;

using StateMat = Eigen::Matrix<double, StateIndex::SIZE, StateIndex::SIZE>;

}  // namespace imu_gnss_estimation_core
