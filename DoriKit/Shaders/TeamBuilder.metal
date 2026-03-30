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
struct CombinationPair {
    int a;
    int b;
};

kernel void maxBandPower(device const AreaItem* areaItems,
                         device const CardStats* cardStats,
                         device const CombinationPair* areaItemCombinations,
                         device const int* cardStatCombinations,
                         constant const int* flags,
                         device MaxBandPowerResult* results,
                         uint2 index [[thread_position_in_grid]]) {
    device const CombinationPair* thisAreaItemCombinations = areaItemCombinations + index[0] * flags[3];
    device const int* thisCardStatCombinations = cardStatCombinations + index[1] * 5;
    
    AreaItem usingAreaItems[64];
    for (int i = 0; i < flags[3]; i++) {
        auto pair = thisAreaItemCombinations[i];
        usingAreaItems[i] = (areaItems + pair.a * flags[2])[pair.b];
    }
    CardStats usingCardStats[5];
    for (int i = 0; i < 5; i++) {
        usingCardStats[i] = cardStats[thisCardStatCombinations[i]];
    }
    
    float performanceFactor = 1;
    float techniqueFactor = 1;
    float visualFactor = 1;
    for (int i = 0; i < flags[3]; i++) {
        thread AreaItem* item = &usingAreaItems[i];
        uint isTargetAttr = min(item->targetAttributes & (1 << uint(flags[0])), uint(1));
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
    bool skill;
};
struct MaxScoreResult {
    uint index1;
    uint index2;
    uint index3;
    float score;
};

kernel void maxScore(device const MaxScoreBandCard* bandCards,
                     constant const int* possibleSkillOrders,
                     device const ChartElement* charts,
                     constant const float* feverBeatRange,
                     constant const int* skillStartIndexs,
                     constant const float* flags,
                     device MaxScoreResult* results,
                     uint3 index [[thread_position_in_grid]]) {
    device const MaxScoreBandCard* thisBandCards = bandCards + index[0] * 5;
    constant const int* skillOrder = possibleSkillOrders + index[1] * 5;
    
    float skillEndBeats[6];
    for (int i = 0; i < 6; i++) {
        constant const int* idx = &skillStartIndexs[i];
        device const ChartElement* ce = &charts[*idx];
        float beat = ce->beat;
        int cardIdx = i < 5 ? skillOrder[i] : index[2];
        device const MaxScoreBandCard* card = &thisBandCards[cardIdx];
        skillEndBeats[i] = beat + card->skillDuration / 60 * flags[4];
    }
    
    int chartElementCount = int(flags[0]);
    float score = 0;
    for (int i = 0; i < chartElementCount; i++) {
        device const ChartElement* chartElement = &charts[i];
        
        float skillBonus = 1.0;
        int skillStartIndex = -1;
        for (int j = 0; j < 6; j++) {
            if (skillStartIndexs[j] <= i) {
                skillStartIndex = j;
            }
        }
        
        if (skillStartIndex > -1 && skillEndBeats[skillStartIndex] > chartElement->beat) {
            int cardIdx;
            if (skillStartIndex < 5) {
                cardIdx = skillOrder[skillStartIndex];
            } else {
                cardIdx = index[2];
            }
            device const MaxScoreBandCard* card = &thisBandCards[cardIdx];
            skillBonus += float(card->skillEffectValue) / 100;
        }
        
        float feverBonus = 1.0;
        if (feverBeatRange[0] < chartElement->beat && feverBeatRange[1] > chartElement->beat) {
            feverBonus = 2.0;
        }
        
        score += float(thisBandCards[0].bandPower) * flags[3] * skillBonus * feverBonus * flags[1];
    }
    
    results[index.z * (uint(flags[5]) * uint(flags[6])) + index.y * uint(flags[5]) + index.x] = MaxScoreResult {
        index[0], index[1], index[2], score
    };
}
