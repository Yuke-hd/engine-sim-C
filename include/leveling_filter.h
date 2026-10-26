#ifndef ATG_ENGINE_SIM_LEVELING_FILTER_H
#define ATG_ENGINE_SIM_LEVELING_FILTER_H

#include "filter.h"

#include "function.h"

class LevelingFilter : public Filter {
    public:
        enum class Detector {
            Peak,
            Rms
        };

    public:
        LevelingFilter();
        virtual ~LevelingFilter();

        virtual float f(float sample);
        float getAttenuation() const { return m_attenuation; }

        void setRmsTimeConstant(float seconds, float sampleRate);

    protected:
        float m_peak;
        float m_meanSquare;
        float m_rmsCoefficient;
        float m_attenuation;

    public:
        float p_maxLevel;
        float p_minLevel;
        float p_target;

        // Output level = p_target * (level / reference)^(1 - p_ratio). 1 normalizes
        // fully to p_target; smaller values let louder input stay louder.
        float p_ratio;

        // Input level that maps to p_target; 0 means p_target itself.
        float p_reference;

        Detector p_detector;
};

#endif /* ATG_ENGINE_SIM_LEVELING_FILTER_H */
