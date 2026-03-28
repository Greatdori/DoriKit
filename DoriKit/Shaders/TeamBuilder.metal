//===---*- Greatdori! -*---------------------------------------------------===//
//
// TeamBuilder.metal
//
// This source file is part of the Greatdori! open source project
//
// Copyright (c) 2026 the Greatdori! project authors
// Licensed under Apache License v2.0
//
// See https://greatdori.com/LICENSE.txt for license information
// See https://greatdori.com/CONTRIBUTORS.txt for the list of Greatdori! project authors
//
//===----------------------------------------------------------------------===//

#include <metal_stdlib>
using namespace metal;

struct AreaItem {
    float performanceBoost;
    float techniqueBoost;
    float visualBoost;
    uint targetAttributes;
};
struct CardStats {
    int performance;
    int technique;
    int visual;
};
struct MaxBandPowerResult {
    uint index1;
    uint index2;
    uint power;
};

kernel void maxBandPower(device const AreaItem* areaItems,
                         device const CardStats* cardStats,
                         device const int* areaItemCombinations,
                         device const int* cardStatCombinations,
                         constant const int* flags,
                         device MaxBandPowerResult* results,
                         uint2 index [[thread_position_in_grid]]) {
    device const int* thisAreaItemCombinations = areaItemCombinations + index[0];
    device const int* thisCardStatCombinations = cardStatCombinations + index[1];
    
    AreaItem usingAreaItems[5];
    CardStats usingCardStats[5];
    for (int i = 0; i < 5; i++) {
        usingAreaItems[i] = areaItems[thisAreaItemCombinations[i]];
        usingCardStats[i] = cardStats[thisCardStatCombinations[i]];
    }
    
    float performanceFactor = 1;
    float techniqueFactor = 1;
    float visualFactor = 1;
    for (int i = 0; i < 5; i++) {
        thread AreaItem* item = &usingAreaItems[i];
        uint isTargetAttr = min(item->targetAttributes & uint(flags[0]), uint(1));
        performanceFactor += item->performanceBoost / 100.0 * isTargetAttr;
        techniqueFactor += item->techniqueBoost / 100.0 * isTargetAttr;
        visualFactor += item->visualBoost / 100.0 * isTargetAttr;
    }
    
    uint power = 0;
    for (int i = 0; i < 5; i++) {
        thread CardStats* stats = &usingCardStats[i];
        power += uint(float(stats->performance) * performanceFactor);
        power += uint(float(stats->technique) * techniqueFactor);
        power += uint(float(stats->visual) * visualFactor);
    }
    
    results[index.y * flags[1] + index.x] = MaxBandPowerResult { index[0], index[1], power };
}

struct MaxScoreBandCard {
    int skillEffectValue;
    float skillDuration;
    int bandPower;
};
struct ChartElement {
    uint8_t type;
    float beat;
};
struct MaxScoreResult {
    uint index1;
    uint index2;
    uint index3;
    float score;
};

template<typename T>
T closest_less_than(constant T* data, uint length, T x);

kernel void maxScore(device const MaxScoreBandCard* bandCards,
                     constant const int* possibleSkillOrders,
                     device const ChartElement* charts,
                     constant const float* feverBeatRange,
                     constant const float* skillStartBeats,
                     constant const float* flags,
                     device MaxScoreResult* results,
                     uint3 index [[thread_position_in_grid]]) {
    device const MaxScoreBandCard* thisBandCards = bandCards + index[0] * 5;
    constant const int* skillOrder = possibleSkillOrders + index[1] * 5;
    
    int chartElementCount = int(flags[0]);
    float2 skillSelector = float2(0, 0); // (index, triggerBeat)
    float score = 0;
    for (int i = 0; i < chartElementCount; i++) {
        device const ChartElement* chartElement = &charts[i];
        
        float skillBonus = 1.0;
        const float skillStartBeat = closest_less_than(skillStartBeats, 6, chartElement->beat);
        
        int cardIdx;
        if (skillSelector[0] < 5) {
            cardIdx = skillOrder[int(skillSelector[0])];
        } else {
            cardIdx = index[2];
        }
        device const MaxScoreBandCard* card = &thisBandCards[cardIdx];
        const float skillEndBeat = skillStartBeat + card->skillDuration / 60 * flags[4];
        
        if (skillEndBeat <= chartElement->beat) {
            skillBonus += float(card->skillEffectValue) / 100;
        }
        
        if (skillStartBeat == chartElement->beat && skillSelector[1] != skillStartBeat) {
            skillSelector[0] += 1;
            skillSelector[1] = skillStartBeat;
        }
        
        float feverBonus = step(chartElement->beat, feverBeatRange[0]) * step(feverBeatRange[1], chartElement->beat) + 1;
        
        score += float(thisBandCards[0].bandPower) * flags[3] * skillBonus * feverBonus * flags[1];
    }
    
    results[index.z * (uint(flags[5]) * uint(flags[6])) + index.y * uint(flags[5]) + index.x] = MaxScoreResult {
        index[0], index[1], index[2], score
    };
}

// Helpers
template<typename T>
T closest_less_than(constant T* data, uint length, T x) {
    int low = 0;
    int high = length - 1;
    int result_idx = -1;

    while (low <= high) {
        int mid = low + (high - low) / 2;
        
        if (data[mid] <= x) {
            result_idx = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    return (result_idx != -1) ? data[result_idx] : 0;
}
