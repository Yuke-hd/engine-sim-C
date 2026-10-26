#include "../include/leveling_filter.h"

#include <cmath>

LevelingFilter::LevelingFilter() {
    m_peak = 30000.0;
    m_meanSquare = 0.0;
    m_rmsCoefficient = 0.9995f;
    m_attenuation = 1.0;
    p_target = 30000.0;
    p_minLevel = 0.0;
    p_maxLevel = 1.0;
    p_ratio = 1.0;
    p_reference = 0.0;
    p_detector = Detector::Peak;
}

LevelingFilter::~LevelingFilter() {
    /* void */
}

void LevelingFilter::setRmsTimeConstant(float seconds, float sampleRate) {
    m_rmsCoefficient = std::exp(-1.0f / (seconds * sampleRate));
}

float LevelingFilter::f(float sample) {
    float level;
    if (p_detector == Detector::Rms) {
        m_meanSquare =
            m_rmsCoefficient * m_meanSquare
            + (1 - m_rmsCoefficient) * sample * sample;
        level = std::sqrt(m_meanSquare);
    }
    else {
        m_peak = 0.999f * m_peak;
        if (std::abs(sample) > m_peak) {
            m_peak = std::abs(sample);
        }

        level = m_peak;
    }

    if (level == 0) return 0;

    const float reference = (p_reference > 0) ? p_reference : p_target;
    const float raw_attenuation = (p_ratio == 1.0f)
        ? p_target / level
        : (p_target / reference) * std::pow(reference / level, p_ratio);

    float attenuation = raw_attenuation;
    if (attenuation < p_minLevel) attenuation = p_minLevel;
    else if (attenuation > p_maxLevel) attenuation = p_maxLevel;

    m_attenuation = 0.9 * m_attenuation + 0.1 * attenuation;

    return sample * m_attenuation;
}
