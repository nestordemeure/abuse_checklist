# Youden Threshold Update

## Summary

The web application now uses **Youden-optimal thresholds** instead of arbitrary fixed thresholds (0.5) for classification. This provides scientifically rigorous, prevalence-independent decision boundaries.

## What Changed

### 1. Backend (R Script: `export_web_model.R`)

- **Added Youden threshold calculation** for each of the 18 models
- Calculates optimal threshold at 25% prevalence (realistic for general medical practice)
- Stores threshold + sensitivity/specificity with each model in `model.json`
- Uses Youden's Index: maximizes (sensitivity + specificity - 1)

### 2. Model JSON (`webapp/model.json`)

Each model now includes:
```json
{
  "youden_threshold": 0.12,
  "youden_sensitivity": 0.612903,
  "youden_specificity": 0.947368,
  "youden_index": 0.560
}
```

Thresholds vary by model:
- Single variables: 0.12-0.30
- Multi-variable models: typically 0.10-0.24
- Full 7-variable model: ~0.17

### 3. Frontend (JavaScript: `webapp/script.js`)

- **Updated `getInterpretation()`** to use model-specific Youden threshold
- Classification logic:
  - **Below threshold - 10%**: Low suspicion
  - **Within ±10% of threshold**: Moderate suspicion
  - **Above threshold + 10%**: High suspicion

- **Added threshold display** in technical details
- Shows: threshold value, sensitivity, specificity

## Why This Matters

### Before (Fixed 0.5 Threshold)
- Arbitrary cutoff with no scientific basis
- Same threshold regardless of available variables
- Not optimized for model performance
- Prevalence-dependent

### After (Youden Threshold)
- **Scientifically optimal**: Maximizes balance between sensitivity and specificity
- **Model-specific**: Each model gets its own optimal threshold
- **Prevalence-independent**: Threshold based on ROC curve, not prevalence
- **Better classification**: Optimized for 25% prevalence (general medical practice)

## Example: How Thresholds Vary

| Model Variables | Youden Threshold | Sens | Spec |
|----------------|------------------|------|------|
| antidepressants alone | 12% | 61% | 95% |
| antidepressants + depression | 18% | 71% | 86% |
| antidepressants + depression + benzodiazepines | 16% | 67% | 90% |
| All 7 variables | 17% | 75% | 92% |

**Key insight**: Models with fewer variables often have lower optimal thresholds because they're less discriminating. Using a fixed 0.5 would miss many true positives with these models!

## Technical Details

### Youden's Index (J)

```
J = Sensitivity + Specificity - 1
```

- Range: 0 to 1
- J = 0: No better than random
- J = 1: Perfect classification
- Finds the point on ROC curve furthest from chance diagonal

### Prevalence Adjustment

The threshold is calculated on **prevalence-adjusted probabilities**:

1. Model outputs probability at 85% training prevalence
2. Adjust to 25% target prevalence using Bayes' theorem
3. Find Youden-optimal threshold on adjusted probabilities
4. Store threshold with model

This ensures the threshold works correctly when users input different prevalence values.

## User Experience

Users will now see:

```
Probability: 18.2% ± 4.5%

Suspicion modérée

━━━━━━━━━━━━━━━━━━━━
Technical Details:
Model: antidepressants_depression • AUC: 0.826
Optimal threshold (Youden): 18.0% • Sens: 71.3% • Spec: 85.7%
```

The classification (suspicion level) is now based on comparing **18.2%** (probability) to **18.0%** (Youden threshold), not an arbitrary 50%.

## Validation

Run the test suite to verify:
```bash
# Open webapp/test.html in browser
python3 -m http.server 8000
# Navigate to http://localhost:8000/test.html
```

All tests should pass with Youden threshold logic.

## References

- Youden, W. J. (1950). "Index for rating diagnostic tests". Cancer. 3: 32–35.
- Fluss, R., Faraggi, D., & Reiser, B. (2005). "Estimation of the Youden Index and its associated cutoff point". Biometrical Journal. 47: 458–472.
