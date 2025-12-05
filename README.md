# Sexual Abuse Suspicion Score - Web Application

## Overview

This web application provides a clinical decision support tool to estimate the probability of sexual abuse based on clinical indicators. It uses a logistic regression model trained on patient data to calculate probabilities based on available information.

## Features

- **Bilingual interface** (French/English)
- **Flexible data input**: Handles missing data ("Don't know" option)
- **Probability estimation**: Provides probability percentages, not just integer scores
- **Clinical interpretation**: Offers recommendations based on probability thresholds
- **Responsive design**: Works on desktop and mobile devices
- **No backend required**: Runs entirely in the browser

## Files

- `index.html` - Main web interface
- `script.js` - JavaScript logic for probability calculation
- `model.json` - Logistic regression model coefficients and metadata
- `README.md` - This file

## How to Use

### For Clinicians

1. Open `index.html` in a web browser
2. Switch to your preferred language (French/English) using the language toggle
3. Fill in the clinical information:
   - For each criterion, select "Yes", "No", or "Don't know"
   - Enter work disability duration in months (or leave blank if unknown)
4. Click "Calculate score" to see the probability estimate
5. Review the interpretation and recommendations
6. The system will warn you if too many variables are unknown

### For Deployment

**Option 1: Local file**
Simply open `index.html` directly in a web browser.

**Option 2: Web server**
Deploy the `webapp/` folder to any web server. For testing locally:

```bash
# Using Python 3
python3 -m http.server 8000
```

Then open http://localhost:8000 in your browser.

## Model Information

The model is based on a logistic regression using 7 clinical variables:

1. **Antidepressants** (taking antidepressants)
2. **Depression** (diagnosis of depression)
3. **Benzodiazepines** (taking benzodiazepines)
4. **Suicide attempt** (history of suicide attempt)
5. **Violence** (exposure to violence)
6. **Gynecological disorders** (documented gynecological issues)
7. **Work disability duration** (months of work disability)

### Model Performance

- **AUC**: 0.938 (excellent discriminative ability)
- **Sensitivity**: 83.7% (detects ~5 out of 6 cases)
- **Specificity**: 94.7% (very few false alarms)
- **PPV**: 98.6% (high probability when flagged)

### Interpretation Thresholds

- **< 30%**: Low suspicion - Continue routine follow-up
- **30-70%**: Moderate suspicion - Explore further in consultations
- **≥ 70%**: High suspicion - In-depth exploration strongly recommended

## Important Limitations

⚠️ **This tool is NOT a diagnostic instrument**

- Based on a limited sample (n=133, 85% abuse cases)
- Significant class imbalance may affect probability estimates
- Should be used as a decision aid, not a diagnosis
- Clinical context and medical judgment are paramount
- A low score does not exclude abuse
- Results must be interpreted within the overall clinical picture

## Technical Details

### Probability Calculation

The application uses the logistic regression formula:

```
P(abuse) = 1 / (1 + exp(-z))

where:
z = β₀ + β₁X₁ + β₂X₂ + ... + βₙXₙ

β₀ = intercept
βᵢ = coefficient for variable i
Xᵢ = value of variable i (1 for yes, 0 for no/unknown)
```

### Handling Missing Data

When variables are marked as "Don't know" or left blank:
- They are treated as 0 (absent) in the calculation
- The system shows a warning if too many variables are unknown
- This is a conservative approach that may underestimate probability

## Updating the Model

To update the model with new data:

1. Update the source data in `data/`
2. Run the data processing: `Rscript scripts/01_import_data.R`
3. Export the new model: `Rscript scripts/export_web_model.R`
4. The new `model.json` will be generated automatically
5. Refresh the web page to use the updated model

## Browser Compatibility

Works with all modern browsers:
- Chrome/Edge (version 90+)
- Firefox (version 88+)
- Safari (version 14+)

Requires JavaScript enabled.

## Privacy

This application runs entirely in the browser. No data is sent to any server. Patient information remains on the user's device.

## License

For research and clinical use only. Not for commercial distribution.

## Contact

For questions or issues, please contact the research team.
