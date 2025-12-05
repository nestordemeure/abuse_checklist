# Understanding the Metrics: Clinical Decision Support System for Sexual Abuse Screening

This document explains all the metrics used in the sexual abuse screening system, in both technical and layman's terms.

## Overview

The system provides a **probability estimate** (e.g., "58% likelihood of sexual abuse") based on clinical indicators. It uses **multiple logistic regression models** - different models for different combinations of available information.

---

## Key Metrics Explained

### 1. **Probability / Likelihood**

**What it is:**
The percentage chance that the patient has experienced sexual abuse, based on the available clinical indicators.

**How to interpret:**
- **< 30%**: Low suspicion - Continue routine follow-up
- **30-70%**: Moderate suspicion - Explore further in consultations
- **≥ 70%**: High suspicion - In-depth exploration strongly recommended

**Important note:**
This is a probability estimate, not a certainty. A 70% probability means that among patients with similar profiles, approximately 7 out of 10 had experienced abuse in our dataset.

---

### 2. **AUC (Area Under the Curve)**

**Technical definition:**
The probability that the model will rank a randomly chosen abuse case higher than a randomly chosen control case.

**Layman's explanation:**
"How good is the model at distinguishing between abuse and non-abuse cases?"

**Interpretation:**
- **0.9-1.0**: Excellent discrimination
- **0.8-0.9**: Good discrimination
- **0.7-0.8**: Fair discrimination
- **0.5-0.7**: Poor discrimination
- **0.5**: No better than random guessing

**Example:**
AUC = 0.938 (our full model) means the model correctly ranks cases 93.8% of the time.

---

### 3. **Sensitivity / Recall** (also called True Positive Rate)

**Technical definition:**
Proportion of actual abuse cases that the system correctly identifies as high-risk.

**Formula:**
Sensitivity = True Positives / (True Positives + False Negatives)

**Layman's explanation:**
"Of all the abuse cases, how many does the system catch?"

**Example:**
- Sensitivity = 80% means:
  - **Detects 8 out of 10 abuse cases** (good)
  - But **misses 2 out of 10 abuse cases** (false negatives)

**Clinical interpretation:**
- **High sensitivity (80-95%)**: Good for screening - catches most cases
- **Low sensitivity (50-70%)**: Will miss many cases - not ideal for screening
- **Trade-off**: Increasing sensitivity usually decreases specificity (more false alarms)

**When it matters:**
Crucial for screening tools. Missing an abuse case (false negative) could mean a patient doesn't get needed support.

---

### 4. **Specificity** (also called True Negative Rate)

**Technical definition:**
Proportion of non-abuse cases (controls) that the system correctly identifies as low-risk.

**Formula:**
Specificity = True Negatives / (True Negatives + False Positives)

**Layman's explanation:**
"Of all the non-abuse cases, how many does the system correctly identify as low-risk?"

**Example:**
- Specificity = 95% means:
  - **Correctly identifies 19 out of 20 non-abuse cases** as low-risk (good)
  - But **1 out of 20 gets incorrectly flagged** as high-risk (false positive)

**Clinical interpretation:**
- **High specificity (95-100%)**: Few false alarms - when it flags a case, it's usually right
- **Low specificity (60-80%)**: Many false alarms - may lead to unnecessary investigations
- **Trade-off**: Increasing specificity usually decreases sensitivity (misses more cases)

**When it matters:**
Important for avoiding false alarms. False positives can cause unnecessary stress and wasted clinical resources.

---

### 5. **Precision / PPV (Positive Predictive Value)**

**Technical definition:**
Of all cases the system flags as high-risk, what proportion actually had abuse?

**Formula:**
PPV = True Positives / (True Positives + False Positives)

**Layman's explanation:**
"When the system says 'high risk', how often is it correct?"

**Example:**
- PPV = 99% means:
  - Of 100 cases flagged as high-risk, **99 are actual abuse cases**
  - Only **1 is a false alarm**

**Clinical interpretation:**
- **High PPV (95-100%)**: Very reliable when positive - can confidently pursue further investigation
- **Low PPV (50-70%)**: Many false alarms - need to be cautious about over-investigating

**Important note:**
PPV depends heavily on the **prevalence** (how common abuse is in your population). In our dataset with 85% abuse cases, PPV is artificially inflated. In general medical practice with lower abuse prevalence, PPV would be lower.

**When it matters:**
Critical for clinical decision-making. High PPV means you can trust a positive result.

---

### 6. **NPV (Negative Predictive Value)**

**Technical definition:**
Of all cases the system flags as low-risk, what proportion truly didn't have abuse?

**Formula:**
NPV = True Negatives / (True Negatives + False Negatives)

**Layman's explanation:**
"When the system says 'low risk', how often is it correct?"

**Example:**
- NPV = 51% means:
  - Of 100 cases flagged as low-risk, **51 truly have no abuse**
  - But **49 are actually abuse cases** (false negatives!) - This is concerning!

**Clinical interpretation:**
- **High NPV (90-100%)**: Can safely rule out abuse when score is low
- **Low NPV (40-60%)**: Low scores DON'T rule out abuse - many cases get missed

**Important note:**
Our models often have lower NPV (40-60%) because of high prevalence in the training data. This means **a low score does NOT mean you can rule out abuse**.

**When it matters:**
Critical for understanding what a negative result means. Low NPV means you can't trust a negative result to rule out abuse.

---

## Understanding the Trade-offs

### The Sensitivity-Specificity Trade-off

You can't maximize both simultaneously. Adjusting the threshold changes the balance:

```
Lower Threshold (e.g., 30%)
├─ Higher Sensitivity (catches more cases)
├─ Lower Specificity (more false alarms)
├─ Lower PPV (less reliable when positive)
└─ Higher NPV (more reliable when negative)

Higher Threshold (e.g., 70%)
├─ Lower Sensitivity (misses more cases)
├─ Higher Specificity (fewer false alarms)
├─ Higher PPV (more reliable when positive)
└─ Lower NPV (less reliable when negative)
```

**Our approach:**
We use the **optimal threshold** (Youden's index) for each model, which balances sensitivity and specificity to maximize overall performance.

---

## Model Performance by Variable Count

| Variables | AUC | Typical Use Case |
|-----------|-----|------------------|
| 1 variable | 0.53-0.78 | Very limited info available |
| 2 variables | 0.74-0.83 | Minimal screening |
| 3 variables | 0.85-0.86 | Basic screening |
| 4-5 variables | 0.87-0.89 | Good screening |
| 6-7 variables | 0.91-0.94 | Comprehensive assessment |

**Key insight:**
More variables = better performance, but even with limited information (1-2 variables), the system provides useful estimates.

---

## Uncertainty and Confidence

### Confidence Interval Width

**What it is:**
The range of uncertainty around the probability estimate.

**Example:**
- Probability: 70%
- CI Width: 0.20 (20 percentage points)
- Means: 95% confident the true probability is between 60% and 80%

**Interpretation:**
- **Narrow CI (<0.10)**: High confidence in the estimate
- **Wide CI (>0.20)**: High uncertainty - take with caution

**What affects it:**
- **Fewer variables**: Wider CI (more uncertainty)
- **Smaller sample size**: Wider CI
- **More variables**: Narrower CI (more confidence)

---

## System Warnings

The system provides different levels of warnings based on data quality:

### 🔴 High Severity
- **More than 4 variables unknown**: Estimate is very uncertain
- **Critical variables missing**: Key predictors (antidepressants, violence) unknown

### 🟡 Medium Severity
- **3-4 variables unknown**: Estimate could vary significantly
- **Small sample size**: Model trained on limited data (n<20 controls)

### 🔵 Low Severity (Informational)
- **1-2 variables unknown**: Minor impact on estimate

---

## Clinical Application

### When to Trust the Results

✅ **High confidence situations:**
- 5+ variables known
- Exact model match found
- Narrow confidence interval
- No high-severity warnings

⚠️ **Use with caution:**
- 3-4 variables known
- Important variables missing
- Wider confidence intervals

❌ **Results unreliable:**
- <3 variables known
- Multiple high-severity warnings
- Very wide confidence intervals

### Remember

1. **Not a diagnosis**: This is a screening tool, not diagnostic
2. **Clinical context**: Always consider the full clinical picture
3. **Low scores don't rule out**: Low NPV means negatives are not conclusive
4. **Follow-up is key**: Use results to guide further exploration, not to make final judgments

---

## Example Interpretations

### Case 1: High Confidence Result
- **Input**: 6 variables known (antidepressants=yes, depression=yes, benzodiazepines=yes, suicide_attempt=yes, gynecological=yes, violence=no)
- **Result**: 95% probability, CI width=0.02
- **Model**: core_6 (AUC=0.913)
- **Interpretation**: Very high confidence. Strong recommendation for in-depth exploration.

### Case 2: Moderate Confidence
- **Input**: 3 variables known (antidepressants=yes, depression=yes, benzodiazepines=yes)
- **Result**: 99% probability, CI width=0.06
- **Model**: medications (AUC=0.856)
- **Interpretation**: High probability but with some uncertainty. Recommend exploration, ideally obtain more information.

### Case 3: Low Confidence
- **Input**: 1 variable known (depression=yes)
- **Result**: 91% probability, CI width=0.12
- **Model**: depression (AUC=0.661)
- **Interpretation**: Model has limited discrimination ability. Result suggests possible concern but should be combined with clinical judgment. Try to obtain more information.

---

## For Researchers and Developers

### Model Selection Algorithm

1. **Exact match**: Find model trained on exactly the known variables
2. **Subset match**: Find largest model that's a subset of known variables
3. **Partial match**: Find model with most overlap

Using subset-specific models (rather than a single model with missing=0) provides **more accurate probability estimates**, especially with few variables known. Improvements can be 10-70 percentage points!

### Training Data

- **n = 133** total (105-131 per model depending on missing data)
- **85% abuse cases** (high prevalence, affects PPV/NPV)
- **15% controls** (small control group, affects specificity estimates)

### Validation

- **Leave-one-out cross-validation** (LOOCV) for all models
- Performance metrics calculated at optimal threshold (Youden's index)
- No external validation yet - results should be validated on independent data

---

## Questions?

For more information about specific aspects of the system:
- Technical documentation: See `README.md`
- Model development: See `scripts/export_web_model_v3_with_uncertainty.R`
- Performance reports: See `outputs/rapport_prediction.md`
