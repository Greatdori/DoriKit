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
