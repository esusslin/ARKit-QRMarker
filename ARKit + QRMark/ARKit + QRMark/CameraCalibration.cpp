//
//  CameraCalibration.cpp
//  ARKit + QRMark
//
//  Created by Eugene Bokhan on 02.08.17.
//  Copyright © 2017 Eugene Bokhan. All rights reserved.
//

#include "CameraCalibration.hpp"

CameraCalibration::CameraCalibration()
{
    
}

CameraCalibration::CameraCalibration(float fx, float fy, float cx, float cy)
{
    for (int i=0; i<3; i++)
        for (int j=0; j<3; j++)
            m_intrinsic.mat[i][j] = 0;
    
    m_intrinsic.mat[0][0] = fx;
    m_intrinsic.mat[1][1] = fy;
    m_intrinsic.mat[0][2] = cx;
    m_intrinsic.mat[1][2] = cy;
    
    for (int i=0; i<4; i++)
        m_distorsion.data[i] = 0;
}

CameraCalibration::CameraCalibration(float fx, float fy, float cx, float cy, float distorsionCoeff[4])
{
    for (int i=0; i<3; i++)
        for (int j=0; j<3; j++)
            m_intrinsic.mat[i][j] = 0;
    
    m_intrinsic.mat[0][0] = fx;
    m_intrinsic.mat[1][1] = fy;
    m_intrinsic.mat[0][2] = cx;
    m_intrinsic.mat[1][2] = cy;
    
    for (int i=0; i<4; i++)
        m_distorsion.data[i] = distorsionCoeff[i];
}

void CameraCalibration::getMatrix34(float cparam[3][4]) const
{
    for (int j=0; j<3; j++)
        for (int i=0; i<3; i++)
            cparam[i][j] = m_intrinsic.mat[i][j];
    
    for (int i=0; i<4; i++)
        cparam[3][i] = m_distorsion.data[i];
}

const Matrix33& CameraCalibration::getIntrinsic() const
{
    return m_intrinsic;
}

const Vector4&  CameraCalibration::getDistorsion() const
{
    return m_distorsion;
}
