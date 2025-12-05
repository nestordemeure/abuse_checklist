// Sexual Abuse Suspicion Score V2 - Web Application
// Uses subset-specific Firth's penalized logistic regression models for accurate probability estimation

let modelData = null;
let currentLanguage = 'fr';

// Load model data from JSON
async function loadModel() {
    try {
        const response = await fetch('model.json');
        modelData = await response.json();
        console.log('Model loaded successfully', modelData);
        console.log(`Available models: ${Object.keys(modelData.models).length}`);
        return true;
    } catch (error) {
        console.error('Error loading model:', error);
        alert('Error loading model. Please refresh the page.');
        return false;
    }
}

// Find exact model match for the given set of known variables
function findBestModel(knownVariables) {
    const knownVarSet = new Set([...knownVariables].sort());

    // Search for exact match only
    for (const [modelName, modelInfo] of Object.entries(modelData.models)) {
        // modelInfo.variables is now always an array (after R export fix)
        const modelVars = modelInfo.variables;
        const modelVarSet = new Set([...modelVars].sort());

        // Check if sets are equal
        if (knownVarSet.size === modelVarSet.size &&
            [...knownVarSet].every(v => modelVarSet.has(v))) {
            console.log(`Exact match found: ${modelName}`);
            return { name: modelName, info: modelInfo, matchType: 'exact' };
        }
    }

    // No exact match found - this should never happen if all 127 combinations exist
    console.error('FATAL: No exact model match found for variables:', knownVariables);
    console.error('Available models:', Object.keys(modelData.models).length);
    throw new Error(`No exact model found for the selected variables: ${knownVariables.join(', ')}. This indicates a critical system error.`);
}

// Uncertainty level definitions (frontend logic, not from backend)
const UNCERTAINTY_LEVELS = [
    {
        threshold: 0.40,
        severity: "high",
        label_fr: "🚨 Incertitude très élevée - Estimation peu fiable",
        label_en: "🚨 Very high uncertainty - Unreliable estimate",
        color: "#dc2626"
    },
    {
        threshold: 0.20,
        severity: "medium",
        label_fr: "⚠️ Incertitude élevée - Interpréter avec prudence",
        label_en: "⚠️ High uncertainty - Interpret with caution",
        color: "#d97706"
    },
    {
        threshold: 0.10,
        severity: "low",
        label_fr: "Incertitude modérée - Probablement fiable",
        label_en: "Moderate uncertainty - Probably reliable",
        color: "#059669"
    },
    {
        threshold: 0,
        severity: "very_low",
        label_fr: "Faible incertitude - Probablement fiable",
        label_en: "Low uncertainty - Probably reliable",
        color: "#059669"
    }
];

// Check which uncertainty level applies based on CI width
// Now uses the corrected CI width from delta method, not the old typical_ci_width
function checkUncertaintyWarnings(knownVariables, unknownVariables, selectedModel, correctedCIWidth) {
    const ciWidth = correctedCIWidth;

    // Find the appropriate uncertainty level (sorted from highest to lowest threshold)
    for (const level of UNCERTAINTY_LEVELS) {
        if (ciWidth >= level.threshold) {
            return [{
                ...level,
                ciWidth: ciWidth
            }];
        }
    }

    // Fallback to lowest uncertainty level
    return [{
        ...UNCERTAINTY_LEVELS[UNCERTAINTY_LEVELS.length - 1],
        ciWidth: ciWidth
    }];
}

// Calculate confidence interval using delta method with covariance matrix
// This properly accounts for prevalence adjustment and coefficient correlation
function calculateConfidenceInterval(model, formDataValues, adjustedLinearPredictor, level = 0.95) {
    const coefficients = model.coefficients;
    const vcov = model.coefficient_vcov;

    if (!vcov) {
        // Fallback to old method if vcov not available
        console.warn('Covariance matrix not available, using approximate CI');
        return {
            lower: null,
            upper: null,
            width: model.typical_ci_width,
            method: 'legacy'
        };
    }

    // Build design vector: [1, x1, x2, ...] for [intercept, var1, var2, ...]
    // Order must match coefficient order
    const coefNames = Object.keys(coefficients);
    const designVector = [];

    for (const coefName of coefNames) {
        if (coefName === '(Intercept)') {
            designVector.push(1);
        } else {
            // Check if this coefficient was activated
            // For boolean variables, coefficient names are like "antidepressantsTRUE"
            // We need to check if the base variable was TRUE
            let activated = 0;

            // Extract variable id from coefficient name
            // Pattern: variableIdTRUE for booleans, variableId for numeric
            const varId = coefName.replace(/TRUE$/, '');

            if (coefName.endsWith('TRUE')) {
                // Boolean variable
                const value = formDataValues[varId];
                activated = (value === true || value === 'yes' || value === 1) ? 1 : 0;
            } else if (varId !== '(Intercept)') {
                // Numeric variable
                const value = formDataValues[varId];
                activated = parseFloat(value) || 0;
            }

            designVector.push(activated);
        }
    }

    // Calculate variance of linear predictor: Var(X'β) = X' Vcov X
    let variance = 0;
    for (let i = 0; i < coefNames.length; i++) {
        for (let j = 0; j < coefNames.length; j++) {
            const vcov_ij = vcov[coefNames[i]][coefNames[j]];
            variance += designVector[i] * designVector[j] * vcov_ij;
        }
    }

    const se = Math.sqrt(variance);

    // Critical value for confidence level
    const z = 1.96; // For 95% CI

    // CI on logit scale (SE doesn't change with prevalence offset)
    const logitLower = adjustedLinearPredictor - z * se;
    const logitUpper = adjustedLinearPredictor + z * se;

    // Transform to probability scale using inverse logit
    const invLogit = (x) => 1 / (1 + Math.exp(-x));
    const probLower = invLogit(logitLower);
    const probUpper = invLogit(logitUpper);

    return {
        lower: probLower,
        upper: probUpper,
        width: probUpper - probLower,
        se: se,
        method: 'delta'
    };
}

// Calculate probability using the appropriate subset model
function calculateProbability(formData) {
    if (!modelData) {
        console.error('Model not loaded');
        return null;
    }

    // Identify known variables
    const knownVariables = [];
    const unknownVariables = [];
    const formDataValues = {};

    modelData.variables.forEach(variable => {
        const value = formData[variable.id];

        if (value === null || value === undefined || value === '') {
            unknownVariables.push(variable);
        } else {
            knownVariables.push(variable.id);
            formDataValues[variable.id] = value;
        }
    });

    console.log('Known variables:', knownVariables);
    console.log('Unknown variables:', unknownVariables.map(v => v.id));

    // If no variables are known, don't calculate anything
    if (knownVariables.length === 0) {
        console.log('No variables known - skipping calculation');
        return null;
    }

    // Find exact model match for this variable set
    let selectedModel;
    try {
        selectedModel = findBestModel(knownVariables);
    } catch (error) {
        console.error('Model selection failed:', error);
        alert(`ERROR: ${error.message}\n\nPlease report this issue.`);
        return null;
    }

    const model = selectedModel.info;
    const coefficients = model.coefficients;

    // Calculate linear predictor using selected model
    let linearPredictor = coefficients['(Intercept)'];

    // model.variables is now always an array
    const modelVariables = model.variables;

    modelVariables.forEach(varId => {
        const value = formDataValues[varId];

        if (value === null || value === undefined) {
            return; // Skip if not available (shouldn't happen with proper model selection)
        }

        // Find variable definition
        const varDef = modelData.variables.find(v => v.id === varId);

        if (varDef.type === 'boolean') {
            if (value === true || value === 'yes' || value === 1) {
                const coeffName = varId + 'TRUE';
                if (coefficients[coeffName] !== undefined) {
                    linearPredictor += coefficients[coeffName];
                }
            }
        } else if (varDef.type === 'numeric') {
            const numValue = parseFloat(value);
            if (!isNaN(numValue) && coefficients[varId] !== undefined) {
                linearPredictor += coefficients[varId] * numValue;
            }
        }
    });

    // Get target prevalence from form (convert from percentage to proportion)
    const targetPrevalenceInput = document.getElementById('target_prevalence');
    const targetPrevalence = targetPrevalenceInput ? parseFloat(targetPrevalenceInput.value) / 100 : 0.25;

    // Get sample prevalence from model metadata
    const samplePrevalence = modelData.prevalence_info.sample_prevalence;

    // Apply prevalence adjustment to linear predictor
    // Formula: adjusted_logit = original_logit - log(p_sample/(1-p_sample)) + log(p_target/(1-p_target))
    const sampleLogOdds = Math.log(samplePrevalence / (1 - samplePrevalence));
    const targetLogOdds = Math.log(targetPrevalence / (1 - targetPrevalence));
    const adjustedLinearPredictor = linearPredictor - sampleLogOdds + targetLogOdds;

    // Apply logistic function to adjusted predictor
    const probability = 1 / (1 + Math.exp(-adjustedLinearPredictor));

    // Calculate confidence interval using delta method
    const ciResult = calculateConfidenceInterval(model, formDataValues, adjustedLinearPredictor);

    // Check for uncertainty warnings (now using corrected CI width)
    const warnings = checkUncertaintyWarnings(knownVariables, unknownVariables, selectedModel, ciResult.width);

    return {
        probability: probability,
        confidenceInterval: {
            lower: ciResult.lower,
            upper: ciResult.upper,
            width: ciResult.width,
            method: ciResult.method
        },
        linearPredictor: linearPredictor,
        adjustedLinearPredictor: adjustedLinearPredictor,
        samplePrevalence: samplePrevalence,
        targetPrevalence: targetPrevalence,
        knownVariables: knownVariables.length,
        unknownVariables: unknownVariables,
        totalVariables: modelData.variables.length,
        selectedModel: selectedModel.name,
        modelMatchType: selectedModel.matchType,
        modelAUC: model.auc,
        modelNObs: model.n_obs,
        modelCIWidth: ciResult.width,  // Use corrected CI width
        youdenThreshold: model.youden_threshold,
        youdenSensitivity: model.youden_sensitivity,
        youdenSpecificity: model.youden_specificity,
        uncertaintyWarnings: warnings
    };
}

// Get interpretation based on probability
function getInterpretation(probability) {
    // Use fixed percentage thresholds for interpretation
    // Low: < 30%, Moderate: 30-70%, High: >= 70%

    if (probability < 0.30) {
        return {
            level: "low",
            label_fr: "Suspicion faible",
            label_en: "Low suspicion",
            recommendation_fr: "Continuer le suivi habituel. Rester attentif aux signaux.",
            recommendation_en: "Continue routine follow-up. Stay alert to signals."
        };
    } else if (probability < 0.70) {
        return {
            level: "moderate",
            label_fr: "Suspicion modérée",
            label_en: "Moderate suspicion",
            recommendation_fr: "Explorer davantage lors des consultations suivantes. Créer un espace de parole sécurisant.",
            recommendation_en: "Explore further in subsequent consultations. Create a safe space for discussion."
        };
    } else {
        return {
            level: "high",
            label_fr: "Suspicion élevée",
            label_en: "High suspicion",
            recommendation_fr: "Une exploration clinique approfondie est fortement recommandée. Considérer une orientation vers un spécialiste.",
            recommendation_en: "In-depth clinical exploration is strongly recommended. Consider referral to a specialist."
        };
    }
}

// Format probability as percentage
function formatProbability(probability) {
    return (probability * 100).toFixed(1);
}

// Collect form data
function collectFormData() {
    const formData = {};

    modelData.variables.forEach(variable => {
        if (variable.type === 'boolean') {
            const selected = document.querySelector(`input[name="${variable.id}"]:checked`);
            if (selected) {
                const value = selected.value;
                if (value === 'yes') {
                    formData[variable.id] = true;
                } else if (value === 'no') {
                    formData[variable.id] = false;
                } else {
                    formData[variable.id] = null;
                }
            } else {
                formData[variable.id] = null;
            }
        } else if (variable.type === 'numeric') {
            const input = document.getElementById(variable.id);
            const value = input.value;
            if (value !== '') {
                formData[variable.id] = parseFloat(value);
            } else {
                formData[variable.id] = null;
            }
        }
    });

    return formData;
}

// Update UI language
function updateLanguage(lang) {
    currentLanguage = lang;

    document.querySelectorAll('[data-text-fr]').forEach(element => {
        if (lang === 'fr' && element.dataset.textFr) {
            element.textContent = element.dataset.textFr;
        } else if (lang === 'en' && element.dataset.textEn) {
            element.textContent = element.dataset.textEn;
        }
    });

    // Update dropdown selection
    const languageSelect = document.getElementById('language-select');
    if (languageSelect) {
        languageSelect.value = lang;
    }
}

// Display results
function displayResults(result) {
    const resultsDiv = document.getElementById('results');
    const interpretation = getInterpretation(result.probability);

    const probabilityPercent = formatProbability(result.probability);

    // Calculate uncertainty (margin of error) as ± half the CI width
    const marginOfError = (result.modelCIWidth / 2 * 100).toFixed(1);

    const label = currentLanguage === 'fr' ? interpretation.label_fr : interpretation.label_en;

    let levelColor = '#2563eb';
    if (interpretation.level === 'moderate') {
        levelColor = '#d97706';
    } else if (interpretation.level === 'high') {
        levelColor = '#dc2626';
    }

    // Determine reliability message based on uncertainty warnings
    let reliabilityLabel = '';
    let reliabilityColor = '#374151'; // Default dark gray

    if (result.uncertaintyWarnings && result.uncertaintyWarnings.length > 0) {
        const warning = result.uncertaintyWarnings[0]; // Use first/most severe warning
        reliabilityLabel = currentLanguage === 'fr' ? warning.label_fr : warning.label_en;
        reliabilityColor = warning.color;
    }

    const resultsHTML = `
        <div class="results-content">
            <div class="probability-display" style="border-color: ${levelColor};">
                <div class="probability-value" style="color: ${levelColor};">
                    ${probabilityPercent}% <span style="font-size: 0.5em; color: #6b7280;">± ${marginOfError}%</span>
                </div>
                <div class="probability-label" data-text-fr="Probabilité d'abus sexuel" data-text-en="Probability of sexual abuse">
                    ${currentLanguage === 'fr' ? 'Probabilité d\'abus sexuel' : 'Probability of sexual abuse'}
                </div>
            </div>

            <div style="text-align: center; font-size: 1.05em; margin: 20px 0; line-height: 1.6;">
                <span style="color: ${levelColor}; font-weight: 600;">${label}</span>${reliabilityLabel ? `<span style="color: #6b7280; margin: 0 10px;">•</span><span style="color: ${reliabilityColor}; font-weight: 600;">${reliabilityLabel}</span>` : ''}
            </div>

            <div style="margin-top: 25px; font-size: 0.85em; color: #9ca3af; text-align: center;">
                ${currentLanguage === 'fr' ? 'Régression de Firth' : 'Firth regression'} • ${currentLanguage === 'fr' ? 'Modèle' : 'Model'} <span style="font-family: monospace;">${result.selectedModel}</span> • AUC: ${result.modelAUC.toFixed(3)} • ${currentLanguage === 'fr' ? 'IC 95%' : '95% CI'}: ±${(result.modelCIWidth * 50).toFixed(1)}% • n=${result.modelNObs}
            </div>
        </div>
    `;

    resultsDiv.innerHTML = resultsHTML;
    resultsDiv.style.display = 'block';
}

// Handle form submission
function handleSubmit(event) {
    event.preventDefault();

    const formData = collectFormData();
    console.log('Form data:', formData);

    const result = calculateProbability(formData);
    console.log('Calculation result:', result);

    if (result) {
        displayResults(result);
    } else {
        alert('Error calculating probability. Please try again.');
    }
}

// Auto-calculate on input change
function autoCalculate() {
    try {
        const formData = collectFormData();
        console.log('Auto-calculating with form data:', formData);

        const result = calculateProbability(formData);
        console.log('Calculation result:', result);

        if (result) {
            displayResults(result);
        } else {
            // Hide results if no calculation was performed
            const resultsDiv = document.getElementById('results');
            resultsDiv.style.display = 'none';
            console.log('No result - results hidden');
        }
    } catch (error) {
        console.error('Error in auto-calculation:', error);
    }
}

// Debounce function for numeric inputs
function debounce(func, wait) {
    let timeout;
    return function(...args) {
        clearTimeout(timeout);
        timeout = setTimeout(() => func.apply(this, args), wait);
    };
}

// Initialize when page loads
document.addEventListener('DOMContentLoaded', async function() {
    const loaded = await loadModel();

    if (!loaded) {
        return;
    }

    const form = document.getElementById('assessment-form');
    form.addEventListener('submit', handleSubmit);

    // Enable auto-mode: hide submit button
    const buttonGroup = document.querySelector('.button-group');
    if (buttonGroup) {
        buttonGroup.classList.add('auto-mode');
    }

    // Add auto-calculation to all radio buttons
    const radios = document.querySelectorAll('input[type="radio"]');
    console.log(`Adding auto-calculation to ${radios.length} radio buttons`);
    radios.forEach(radio => {
        radio.addEventListener('change', () => {
            console.log(`Radio changed: ${radio.name} = ${radio.value}`);
            autoCalculate();
        });
    });

    // Add auto-calculation to numeric inputs (with debounce)
    const numericInput = document.getElementById('work_disability_months');
    if (numericInput) {
        numericInput.addEventListener('input', debounce(() => {
            console.log(`Numeric input changed: ${numericInput.value}`);
            autoCalculate();
        }, 500));
    }

    // Add auto-calculation to prevalence input (with debounce)
    const prevalenceInput = document.getElementById('target_prevalence');
    if (prevalenceInput) {
        prevalenceInput.addEventListener('input', debounce(() => {
            console.log(`Prevalence changed: ${prevalenceInput.value}%`);
            autoCalculate();
        }, 500));
    }

    // Language toggle
    const languageSelect = document.getElementById('language-select');
    if (languageSelect) {
        languageSelect.addEventListener('change', function() {
            const lang = this.value;
            updateLanguage(lang);
            // Re-display results with new language if they exist
            const resultsDiv = document.getElementById('results');
            if (resultsDiv.style.display === 'block') {
                autoCalculate();
            }
        });
    }
});
