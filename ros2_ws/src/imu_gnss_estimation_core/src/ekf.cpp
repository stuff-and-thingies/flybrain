#include "imu_gnss_estimation_core/ekf.hpp"

namespace imu_gnss_estimation_core
{

BasicEkf::BasicEkf(const EkfConfig& config) : config_(config) { reset(); }

void BasicEkf::reset()
{
    x_.setZero();
    P_.setZero();

    P_(StateIndex::PN, StateIndex::PN) =
        config_.init_std_p * config_.init_std_p;
    P_(StateIndex::PE, StateIndex::PE) =
        config_.init_std_p * config_.init_std_p;
    P_(StateIndex::PD, StateIndex::PD) =
        config_.init_std_p * config_.init_std_p;
    P_(StateIndex::VN, StateIndex::VN) =
        config_.init_std_v * config_.init_std_v;
    P_(StateIndex::VE, StateIndex::VE) =
        config_.init_std_v * config_.init_std_v;
    P_(StateIndex::VD, StateIndex::VD) =
        config_.init_std_v * config_.init_std_v;

    initialized_ = true;
}

void BasicEkf::predict_imu(const ImuAccelSample& imu, double dt)
{
    if (!initialized_ || dt <= 0.0 || dt >= 0.1)
    {
        return;
    }

    const Eigen::Matrix3d R_ned_body =
        latest_quaternion_.normalized().toRotationMatrix();

    Eigen::Vector3d accel_ned = R_ned_body * imu.accel_body_frd_mps2;

    if (config_.add_gravity)
    {
        accel_ned(2) += config_.gravity_mps2;
    }

    x_(StateIndex::PN) +=
        x_(StateIndex::VN) * dt + 0.5 * accel_ned(0) * dt * dt;
    x_(StateIndex::PE) +=
        x_(StateIndex::VE) * dt + 0.5 * accel_ned(1) * dt * dt;
    x_(StateIndex::PD) +=
        x_(StateIndex::VD) * dt + 0.5 * accel_ned(2) * dt * dt;

    x_(StateIndex::VN) += accel_ned(0) * dt;
    x_(StateIndex::VE) += accel_ned(1) * dt;
    x_(StateIndex::VD) += accel_ned(2) * dt;

    StateMat F;
    F.setIdentity();
    F.block<3, 3>(StateIndex::PN, StateIndex::VN) =
        Eigen::Matrix3d::Identity() * dt;

    StateMat Q;
    Q.setZero();

    const double qp2 = config_.q_std_p * config_.q_std_p;
    const double qv2 = config_.q_std_v * config_.q_std_v;

    Q(StateIndex::PN, StateIndex::PN) = qp2 * dt;
    Q(StateIndex::PE, StateIndex::PE) = qp2 * dt;
    Q(StateIndex::PD, StateIndex::PD) = qp2 * dt;

    Q(StateIndex::VN, StateIndex::VN) = qv2 * dt;
    Q(StateIndex::VE, StateIndex::VE) = qv2 * dt;
    Q(StateIndex::VD, StateIndex::VD) = qv2 * dt;

    P_ = F * P_ * F.transpose() + Q;

    enforce_covariance_safety();
}

UpdateResult BasicEkf::update_gnss_velocity(const GnssVelocitySample& gnss)
{
    UpdateResult result;

    Eigen::Matrix<double, 3, StateIndex::SIZE> H;

    H.setZero();
    H.block<3, 3>(0, StateIndex::VN) = Eigen::Matrix3d::Identity();

    const Eigen::Vector3d z = gnss.velocity_ned_mps;
    const Eigen::Vector3d h = x_.segment<3>(StateIndex::VN);
    const Eigen::Vector3d r = z - h;

    result = update_generic(r, H, gnss.covariance);

    return result;
}

void BasicEkf::store_quaternion_sample(const OdometrySample& odom)
{
    latest_quaternion_ = odom.q_ned_body;
}

void BasicEkf::enforce_covariance_safety()
{
    // enforce symmetry
    P_ = 0.5 * (P_ + P_.transpose());

    // diagonal entires should be >= 0
    P_.diagonal() = P_.diagonal().cwiseMax(1e-9);

    // restrict diagonal entries from growing infinitely
    P_.diagonal() = P_.diagonal().cwiseMin(1e6);
}

UpdateResult BasicEkf::update_generic(const Eigen::VectorXd& residual,
                                      const Eigen::MatrixXd& H,
                                      const Eigen::MatrixXd& R)
{
    UpdateResult result;

    if (!initialized_)
    {
        result.accepted = false;
        result.residual.setZero();
        return result;
    }

    Eigen::MatrixXd S = H * P_ * H.transpose() + R;

    Eigen::MatrixXd K = P_ * H.transpose() * S.inverse();

    Eigen::Vector<double, StateIndex::SIZE> correction = K * residual;

    x_ += correction;

    StateMat I;
    I.setIdentity();

    P_ = (I - K * H) * P_ * (I - K * H).transpose() + K * R * K.transpose();

    enforce_covariance_safety();

    result.residual = residual;
    result.accepted = true;

    return result;
}

const StateVec& BasicEkf::state() const { return x_; }

const StateMat& BasicEkf::covariance() const { return P_; }

}  // namespace imu_gnss_estimation_core
